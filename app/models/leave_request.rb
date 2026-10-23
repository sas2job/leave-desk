class LeaveRequest < ApplicationRecord
  COMMENT_MAX_LENGTH = 2_000

  class InvalidTransition < StandardError; end
  class ReviewNotAuthorized < StandardError; end

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
  validates :employee_comment, length: { maximum: COMMENT_MAX_LENGTH }, if: :will_save_change_to_employee_comment?
  validates :review_comment, length: { maximum: COMMENT_MAX_LENGTH }, if: :will_save_change_to_review_comment?
  validate :dates_are_supported
  validate :dates_are_in_current_year, on: :create
  validate :ends_on_is_not_before_starts_on
  validate :reviewer_is_not_employee
  validate :leave_type_is_active, on: :create
  validate :period_does_not_overlap_active_request
  validate :period_boundaries_are_in_order
  validate :birthday_leave_is_one_full_day, on: :create
  validate :duration_is_positive
  validate :leave_type_id_has_valid_syntax
  validate :calculation_inputs_are_unchanged, on: :update
  before_validation :store_duration, on: :create
  after_create :record_created_event
  after_create :record_calendar_unverified_event, if: :calendar_unverified?

  def save(**options)
    with_persistence_locks { super }
  end

  def save!(**options)
    with_persistence_locks { super }
  end

  def approve!(by:, comment: nil)
    review!(new_status: :approved, by:, comment:)
  end

  def reject!(by:, comment: nil)
    review!(new_status: :rejected, by:, comment:)
  end

  def cancel!(by: employee)
    with_lock do
      raise InvalidTransition, "Отменить можно только заявку на рассмотрении или одобренную заявку" unless pending? || approved?

      previous_status = status
      update!(status: :cancelled)
      record_event!(:cancelled, by:, from_status: previous_status)
    end
  end

  def duration_in_days
    if persisted? && duration_half_days
      return duration_half_days.even? ? duration_half_days / 2 : duration_half_days / 2.0
    end

    calendar_duration_in_days
  end

  def calendar_duration_in_days
    return if leave_type.blank? || !dates_supported? || ends_on < starts_on

    days = ends_on.jd - starts_on.jd + 1
    days -= RussianFederalHoliday.count_between(starts_on, ends_on) if leave_type.exclude_public_holidays?
    days -= 0.5 if starts_afternoon? && counted_calendar_date?(starts_on)
    days -= 0.5 if ends_morning? && counted_calendar_date?(ends_on)
    days
  end

  def calendar_years
    return [] unless dates_supported? && ends_on >= starts_on

    (starts_on.year..ends_on.year).to_a
  end

  def reconcile_calendar!(by:)
    raise InvalidTransition, "Проверить календарь может только администратор" unless by&.administrator?

    FederalCalendar.with_year_locks(calendar_years) do
      FederalCalendar.uncached do
        calendars = FederalCalendar.where(year: calendar_years).order(:year).lock("FOR UPDATE").load
        missing_years = calendar_years - calendars.map(&:year)
        raise InvalidTransition, missing_calendars_message(missing_years) if missing_years.any?

        with_lock do
          raise InvalidTransition, "Календарь заявки уже проверен" unless calendar_unverified?

          new_duration = calendar_duration_in_days
          raise InvalidTransition, "Новый расчёт не даёт положительной длительности" unless new_duration&.positive?

          previous_duration = duration_in_days
          update!(duration_half_days: (new_duration * 2).to_i, calendar_unverified: false)
          record_event!(:calendar_reconciled, by:, from_status: status,
            comment: "Продолжительность: #{previous_duration} → #{new_duration} дн.")
        end
      end
    end
  end

  def flag_calendar_for_review!
    with_lock do
      return unless pending? || approved?
      return if calendar_unverified?

      update!(calendar_unverified: true)
      record_event!(:calendar_unverified, by: nil, from_status: status,
        comment: "Праздничные даты изменились; расчёт требует проверки администратора")
    end
  end

  private

  def with_persistence_locks
    return yield unless leave_type_id.present? && (new_record? || will_save_change_to_leave_type_id?)

    self.class.transaction do
      locked_type = LeaveType.uncached do
        LeaveType.where(id: leave_type_id).lock("FOR UPDATE").first
      end
      association(:leave_type).target = locked_type
      if new_record?
        with_calendar_locks do
          lock_employee_for_creation
          yield
        end
      else
        yield
      end
    end
  end

  def with_calendar_locks
    return yield if calendar_years.empty?

    FederalCalendar.with_year_locks(calendar_years) do
      FederalCalendar.uncached do
        FederalCalendar.where(year: calendar_years).order(:year).lock("FOR UPDATE").load
        yield
      end
    end
  end

  def lock_employee_for_creation
    locked_employee = User.uncached do
      User.where(id: employee_id).lock("FOR UPDATE").first
    end
    association(:employee).target = locked_employee
  end

  def leave_type_id_has_valid_syntax
    raw_id = attribute_before_type_cast("leave_type_id")
    return if raw_id.is_a?(Integer) && raw_id.positive?
    return if raw_id.is_a?(String) && raw_id.match?(/\A[1-9]\d*\z/)

    errors.add(:leave_type, "должен быть выбран из списка")
  end

  def dates_are_supported
    errors.add(:starts_on, SupportedCalendarPeriod.date_error) if starts_on && !supported_date?(starts_on)
    errors.add(:ends_on, SupportedCalendarPeriod.date_error) if ends_on && !supported_date?(ends_on)
  end

  def dates_are_in_current_year
    return unless dates_supported?
    return if starts_on.year == Date.current.year && ends_on.year == Date.current.year

    errors.add(:base, "Оформить отсутствие можно только в текущем календарном году")
  end

  def calculation_inputs_are_unchanged
    fields = %i[leave_type_id starts_on ends_on start_part end_part]
    return unless fields.any? { |field| will_save_change_to_attribute?(field) }

    errors.add(:base, "Даты и способ расчёта сохранённой заявки нельзя изменить; отмените её и создайте новую")
  end

  def store_duration
    FederalCalendar.uncached do
      calculated_duration = duration_in_days
      self.duration_half_days = (calculated_duration * 2).to_i if calculated_duration
      years = calendar_years
      self.calendar_unverified = FederalCalendar.where(year: years).count != years.size if years.any?
    end
  end

  def missing_calendars_message(years)
    return "Календарь #{years.first} года ещё не внесён" if years.one?

    "Календари #{years.join(', ')} годов ещё не внесены"
  end

  def dates_supported?
    supported_date?(starts_on) && supported_date?(ends_on)
  end

  def supported_date?(date)
    date.is_a?(Date) && SupportedCalendarPeriod::DATES.cover?(date)
  end

  def review!(new_status:, by:, comment:)
    with_lock do
      raise InvalidTransition, "Сотрудник не может согласовать собственную заявку" if by&.id == employee_id
      current_employee = User.uncached do
        User.where(id: employee_id).lock("FOR UPDATE").first
      end
      raise ReviewNotAuthorized unless by && current_employee&.manager_id == by.id
      raise InvalidTransition, "Рассмотреть можно только заявку на рассмотрении" unless pending?

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
    errors.add(:reviewer, "не может согласовать собственную заявку") if reviewer && reviewer == employee
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

  def birthday_leave_is_one_full_day
    return unless leave_type&.code == "BIRTHDAY"
    return unless dates_supported? && ends_on >= starts_on
    return if start_part.nil? || end_part.nil?
    return if starts_on == ends_on && starts_morning? && ends_afternoon?

    errors.add(:base, "Выходной в день рождения можно оформить только на один полный день")
  end

  def duration_is_positive
    return if leave_type.blank? || !dates_supported?
    return if ends_on < starts_on
    return if starts_on == ends_on && starts_afternoon? && ends_morning?
    return unless leave_type.exclude_public_holidays?

    duration = new_record? ? duration_half_days && duration_half_days / 2.0 : duration_in_days
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

  def record_calendar_unverified_event
    record_event!(:calendar_unverified, by: nil, from_status: status,
      comment: "Календарь года ещё не внесён; расчёт требует проверки администратора")
  end

  def record_event!(event_type, by:, from_status:, comment: nil)
    events.create!(event_type:, actor: by,
      from_status: from_status && self.class.statuses.fetch(from_status),
      to_status: self.class.statuses.fetch(status), comment:, occurred_at: Time.current)
  end
end
