module StatutoryLeaveRules
  extend ActiveSupport::Concern

  included do
    enum :care_relationship, { mother: 0, father: 1, relative: 2, guardian: 3, foster_parent: 4 }, prefix: :care, validate: { allow_nil: true }
    belongs_to :resumes_request, class_name: "LeaveRequest", optional: true
    has_one :legal_review, class_name: "LeaveLegalReview", dependent: :restrict_with_exception
    attr_readonly :legal_kind, :child_born_on, :care_relationship, :resumes_request_id
    before_validation :set_legal_kind, on: :create
    validate :statutory_period_is_full_days, on: :create
    validate :childcare_period_is_valid, on: :create
    validate :resumption_is_valid, on: :create
    validate :birthday_is_available_this_year, on: :create
  end

  def annual_leave?
    legal_kind == 1 || leave_type&.code == "ANNUAL"
  end

  def maternity_leave?
    legal_kind == 2 || leave_type&.code == "MATERNITY"
  end

  def childcare_leave?
    legal_kind == 3 || leave_type&.code == "CHILDCARE"
  end

  def family_leave?
    maternity_leave? || childcare_leave?
  end

  def statutory_leave?
    annual_leave? || family_leave?
  end

  def statutory_excludes_holidays?
    return false if sick_leave?
    annual_leave? || (!family_leave? && leave_type.exclude_public_holidays?)
  end

  def full_calendar_days?
    precise_time? ? start_minute.zero? && end_minute == LeaveRequest::MINUTES_PER_DAY : starts_morning? && ends_afternoon?
  end

  def register_family!(by:, legal_review:)
    raise LeaveRequest::InvalidTransition, "Кадровая регистрация предназначена для семейных отпусков" unless family_leave?

    review!(new_status: :approved, by:, comment: nil, legal_review:, family_registration: true)
  end

  def request_clarification!(by:, comment:)
    with_lock do
      raise LeaveRequest::ReviewNotAuthorized unless by&.active? && by.administrator? && by.id != employee_id
      raise LeaveRequest::InvalidTransition, "Уточнение доступно для незарегистрированного семейного отпуска" unless family_leave? && pending?
      raise LeaveRequest::InvalidTransition, "Укажите, какие сведения нужно уточнить" if comment.blank?

      record_event!(:statutory_clarification, by:, from_status: status, comment:)
    end
  end

  def return_from_childcare!(by:, return_on:)
    with_lock do
      current_employee = User.uncached { User.lock.find(employee_id) }
      association(:employee).target = current_employee
      raise LeaveRequest::ReviewNotAuthorized unless by&.id == employee_id && current_employee.active?
      raise LeaveRequest::InvalidTransition, "Выход доступен только из действующего отпуска по уходу" unless approved? && childcare_leave? &&
        starts_on <= employee_today && ends_on >= employee_today
      unless return_on.is_a?(Date) && return_on >= employee_today && return_on >= starts_on && return_on <= ends_on
        raise LeaveRequest::InvalidTransition, "Дата выхода должна быть не раньше сегодняшнего дня и в пределах отпуска"
      end
      update!(status: :interrupted, returned_on: return_on)
      record_event!(:childcare_returned, by:, from_status: :approved,
        comment: "Заявление работника: выход #{return_on.strftime('%d.%m.%Y')}")
    end
  end

  private

  def set_legal_kind
    self.legal_kind = { "ANNUAL" => 1, "MATERNITY" => 2, "CHILDCARE" => 3, "BIRTHDAY" => 4, "SICK" => 5 }.fetch(leave_type&.code, 0)
    self.birthday_claim_year = starts_on.year if legal_kind == 4 && supported_date?(starts_on)
    if leave_type&.full_day_only? && start_time.nil? && end_time.nil? && starts_morning? && ends_afternoon?
      self.start_time = "00:00"
      self.end_time = "24:00"
    end
  end

  def birthday_is_available_this_year
    return unless leave_type&.code == "BIRTHDAY" && supported_date?(starts_on) && employee_id

    used = self.class.joins(:leave_type).where(employee_id:, leave_types: { code: "BIRTHDAY" })
      .where(starts_on: starts_on.beginning_of_year..starts_on.end_of_year)
      .where("leave_requests.status IN (0, 1) OR leave_requests.birthday_used = TRUE").exists?
    errors.add(:base, "Выходной в день рождения можно использовать только один раз за календарный год") if used
  end

  def statutory_period_is_full_days
    return unless statutory_leave? && dates_supported?
    return if full_calendar_days?

    errors.add(:base, "Ежегодный и семейные отпуска оформляются на полные календарные дни (00:00–24:00)")
  end

  def childcare_period_is_valid
    return unless childcare_leave?
    unless child_born_on.is_a?(Date) && SupportedCalendarPeriod::DATES.cover?(child_born_on) && child_born_on <= Date.current
      errors.add(:child_born_on, "укажите действительную дату рождения ребёнка")
      return
    end
    errors.add(:care_relationship, "укажите, кто осуществляет уход") if care_relationship.nil?
    limit = child_born_on.advance(years: 3)
    limit += 1 if child_born_on.month == 2 && child_born_on.day == 29
    if dates_supported? && (starts_on < child_born_on || ends_on > limit)
      errors.add(:base, "Отпуск по уходу возможен от рождения до дня трёхлетия ребёнка включительно")
    end
  end

  def resumption_is_valid
    return unless resumes_request_id
    source = resumes_request
    unless childcare_leave? && source&.interrupted? && source.childcare_leave? && source.employee_id == employee_id &&
        source.child_born_on == child_born_on && source.care_relationship == care_relationship &&
        starts_on.is_a?(Date) && starts_on >= source.returned_on
      errors.add(:resumes_request, "возобновить можно свой прерванный отпуск по уходу для того же ребёнка")
    end
  end
end
