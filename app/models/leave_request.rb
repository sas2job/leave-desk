class LeaveRequest < ApplicationRecord
  class InvalidTransition < StandardError; end

  SUPPORTED_DATES = Date.new(2000, 1, 1)..Date.new(2100, 12, 31)

  enum :status, { pending: 0, approved: 1, rejected: 2, cancelled: 3 }
  enum :start_part, { morning: 0, afternoon: 1 }, prefix: :starts,
    default: :morning, validate: true
  enum :end_part, { morning: 0, afternoon: 1 }, prefix: :ends,
    default: :afternoon, validate: true

  belongs_to :employee, class_name: "User", inverse_of: :leave_requests
  belongs_to :leave_type
  belongs_to :reviewer, class_name: "User", inverse_of: :reviewed_leave_requests,
    optional: true
  has_many :events, class_name: "LeaveRequestEvent", dependent: :restrict_with_exception

  validates :starts_on, :ends_on, presence: true
  validate :dates_are_supported
  validate :ends_on_is_not_before_starts_on
  validate :reviewer_is_not_employee
  validate :leave_type_is_active, on: :create
  validate :period_does_not_overlap_active_request
  validate :period_boundaries_are_in_order
  validate :duration_is_positive
  validate :leave_type_id_has_valid_syntax
  after_create :record_created_event

  def approve!(by:, comment: nil)
    review!(new_status: :approved, by:, comment:)
  end

  def reject!(by:, comment: nil)
    review!(new_status: :rejected, by:, comment:)
  end

  def cancel!(by: employee)
    with_lock do
      raise InvalidTransition, "only pending or approved requests can be cancelled" unless pending? || approved?

      previous_status = status
      update!(status: :cancelled)
      record_event!(:cancelled, by:, from_status: previous_status)
    end
  end

  def duration_in_days
    return if leave_type.blank? || !dates_supported? || ends_on < starts_on

    days = ends_on.jd - starts_on.jd + 1
    days -= RussianFederalHoliday.count_between(starts_on, ends_on) if leave_type.exclude_public_holidays?
    days -= 0.5 if starts_afternoon? && counted_calendar_date?(starts_on)
    days -= 0.5 if ends_morning? && counted_calendar_date?(ends_on)
    days
  end

  private

  def leave_type_id_has_valid_syntax
    raw_id = attribute_before_type_cast("leave_type_id")
    return if raw_id.is_a?(Integer) && raw_id.positive?
    return if raw_id.is_a?(String) && raw_id.match?(/\A[1-9]\d*\z/)

    errors.add(:leave_type, "должен быть выбран из списка")
  end

  def dates_are_supported
    errors.add(:starts_on, "должна быть между 01.01.2000 и 31.12.2100") if starts_on && !supported_date?(starts_on)
    errors.add(:ends_on, "должна быть между 01.01.2000 и 31.12.2100") if ends_on && !supported_date?(ends_on)
  end

  def dates_supported?
    supported_date?(starts_on) && supported_date?(ends_on)
  end

  def supported_date?(date)
    date.is_a?(Date) && SUPPORTED_DATES.cover?(date)
  end

  def review!(new_status:, by:, comment:)
    with_lock do
      raise InvalidTransition, "only pending requests can be reviewed" unless pending?
      raise InvalidTransition, "employees cannot review their own requests" if by == employee

      previous_status = status
      update!(status: new_status, reviewer: by, reviewed_at: Time.current,
        review_comment: comment)
      record_event!(new_status, by:, from_status: previous_status, comment:)
    end
  end

  def ends_on_is_not_before_starts_on
    return unless dates_supported?
    return if ends_on >= starts_on

    errors.add(:base, "Дата окончания не может быть раньше даты начала")
  end

  def reviewer_is_not_employee
    errors.add(:reviewer, "не может согласовать собственную заявку") if reviewer == employee
  end

  def leave_type_is_active
    errors.add(:leave_type, "недоступен для оформления") if leave_type && !leave_type.active?
  end

  def period_does_not_overlap_active_request
    return if employee_id.blank? || !dates_supported?
    return unless pending? || approved?

    overlapping_request = self.class.where(employee_id:, status: %i[pending approved])
      .where.not(id:).where("starts_on <= ? AND ends_on >= ?", ends_on, starts_on)
      .any? { |request| time_slots_overlap?(request) }
    errors.add(:base, "Период пересекается с другой активной заявкой") if overlapping_request
  end

  def period_boundaries_are_in_order
    return unless dates_supported?
    return if starts_on < ends_on
    return unless starts_on == ends_on && starts_afternoon? && ends_morning?

    errors.add(:base, "Период отсутствия не может начаться после полудня и закончиться " \
      "до полудня того же дня. Выберите окончание «До конца дня» или укажите следующую дату")
  end

  def duration_is_positive
    return if leave_type.blank? || !dates_supported?
    return if ends_on < starts_on
    return if starts_on == ends_on && starts_afternoon? && ends_morning?
    return unless leave_type.exclude_public_holidays?

    duration = duration_in_days
    return if duration.nil? || duration.positive?

    errors.add(:base, "На эти даты оформить «#{leave_type.name}» не получится: " \
      "весь выбранный период приходится на праздничные дни, которые не засчитываются " \
      "в отпуск. Если вы отсутствуете из-за болезни, выберите «Больничный». " \
      "В остальных случаях укажите другие даты")
  end

  def time_slots_overlap?(other)
    period_start_slot(self) < period_end_slot(other) &&
      period_start_slot(other) < period_end_slot(self)
  end

  def period_start_slot(request)
    request.starts_on.jd * 2 + (request.starts_afternoon? ? 1 : 0)
  end

  def period_end_slot(request)
    request.ends_on.jd * 2 + (request.ends_morning? ? 1 : 2)
  end

  def counted_calendar_date?(date)
    leave_type.include_public_holidays? || !RussianFederalHoliday.on?(date)
  end

  def record_created_event
    record_event!(:created, by: employee, from_status: nil, comment: employee_comment)
  end

  def record_event!(event_type, by:, from_status:, comment: nil)
    events.create!(event_type:, actor: by,
      from_status: from_status && self.class.statuses.fetch(from_status),
      to_status: self.class.statuses.fetch(status), comment:, occurred_at: Time.current)
  end
end
