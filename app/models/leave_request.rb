class LeaveRequest < ApplicationRecord
  class InvalidTransition < StandardError; end

  enum :status, { pending: 0, approved: 1, rejected: 2, cancelled: 3 }
  enum :start_part, { morning: 0, afternoon: 1 }, prefix: :starts, default: :morning
  enum :end_part, { morning: 0, afternoon: 1 }, prefix: :ends, default: :afternoon

  belongs_to :employee, class_name: "User", inverse_of: :leave_requests
  belongs_to :leave_type
  belongs_to :reviewer, class_name: "User", inverse_of: :reviewed_leave_requests,
    optional: true
  has_many :events, class_name: "LeaveRequestEvent", dependent: :restrict_with_exception

  validates :starts_on, :ends_on, presence: true
  validate :ends_on_is_not_before_starts_on
  validate :reviewer_is_not_employee
  validate :leave_type_is_active, on: :create
  validate :period_does_not_overlap_active_request
  validate :period_boundaries_are_in_order
  validate :duration_is_positive
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
    return if leave_type.blank? || starts_on.blank? || ends_on.blank? || ends_on < starts_on

    days = (starts_on..ends_on).count do |date|
      leave_type.include_public_holidays? || !RussianFederalHoliday.on?(date)
    end
    days -= 0.5 if starts_afternoon? && counted_calendar_date?(starts_on)
    days -= 0.5 if ends_morning? && counted_calendar_date?(ends_on)
    days
  end

  private

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
    return if starts_on.blank? || ends_on.blank? || ends_on >= starts_on

    errors.add(:base, "Дата окончания не может быть раньше даты начала")
  end

  def reviewer_is_not_employee
    errors.add(:reviewer, "не может согласовать собственную заявку") if reviewer == employee
  end

  def leave_type_is_active
    errors.add(:leave_type, "недоступен для оформления") if leave_type && !leave_type.active?
  end

  def period_does_not_overlap_active_request
    return if employee_id.blank? || starts_on.blank? || ends_on.blank?
    return unless pending? || approved?

    overlapping_request = self.class.where(employee_id:, status: %i[pending approved])
      .where.not(id:).where("starts_on <= ? AND ends_on >= ?", ends_on, starts_on)
      .any? { |request| time_slots_overlap?(request) }
    errors.add(:base, "Период пересекается с другой активной заявкой") if overlapping_request
  end

  def period_boundaries_are_in_order
    return if starts_on.blank? || ends_on.blank? || starts_on < ends_on
    return unless starts_on == ends_on && starts_afternoon? && ends_morning?

    errors.add(:base, "Период отсутствия не может начаться после полудня и закончиться " \
      "до полудня того же дня. Выберите окончание «До конца дня» или укажите следующую дату")
  end

  def duration_is_positive
    return if leave_type.blank? || starts_on.blank? || ends_on.blank?
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
