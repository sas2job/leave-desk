module InternalSickLeave
  extend ActiveSupport::Concern

  LONG_PERIOD_DAYS = 30

  included do
    has_many :sick_leave_extensions, dependent: :restrict_with_exception
    validate :sick_period_is_full_days, on: :create
    validate :sick_closure_is_unchanged, on: :update
  end

  def sick_leave?
    legal_kind == 5 || leave_type&.code == "SICK"
  end

  def sick_open?
    sick_leave? && approved? && sick_closed_on.nil?
  end

  def sick_needs_clarification?
    sick_open? && ends_on < employee_today
  end

  def long_sick_period?
    sick_leave? && starts_on && ends_on && (ends_on - starts_on).to_i + 1 > LONG_PERIOD_DAYS
  end

  def close_sick_leave!(by:, closed_on:)
    with_lock do
      lock_sick_employee!
      raise LeaveRequest::ReviewNotAuthorized unless by&.active? && by.id == employee_id && employee.active?
      require_open_sick_leave!
      unless closed_on.is_a?(Date) && closed_on >= starts_on && closed_on <= ends_on && closed_on <= employee_today
        raise LeaveRequest::InvalidTransition, "Дата закрытия должна входить в подтверждённый период и быть не позже сегодняшнего дня"
      end
      previous_end = ends_on
      change_sick_period!(ends_on: closed_on, sick_closed_on: closed_on, sick_closed_at: Time.current)
      withdraw_sick_extensions!(by:)
      record_event!(:sick_closed, by:, from_status: status,
        comment: "Фактическое окончание: #{closed_on.strftime('%d.%m.%Y')}; прежнее окончание: #{previous_end.strftime('%d.%m.%Y')}")
    end
  end

  # The caller holds the request and employee locks throughout the transition.
  def change_sick_period!(**attributes)
    require_open_sick_leave!
    @changing_sick_period = true
    assign_attributes(attributes)
    self.start_minute = 0
    self.end_minute = LeaveRequest::MINUTES_PER_DAY
    self.duration_minutes = calendar_duration_in_minutes
    self.duration_half_days = nil
    save!
  ensure
    @changing_sick_period = false
  end

  def lock_sick_employee!
    association(:employee).target = User.uncached { User.lock.find(employee_id) }
  end

  def require_open_sick_leave!
    raise LeaveRequest::InvalidTransition, "Действие доступно только для подтверждённого незакрытого больничного" unless sick_open?
    raise LeaveRequest::InvalidTransition, "Исторический неполный больничный требует отдельного уточнения" unless full_calendar_days?
  end

  def withdraw_sick_extensions!(by:)
    sick_leave_extensions.pending.each do |extension|
      extension.update!(status: :withdrawn)
      record_event!(:sick_extension_withdrawn, by:, from_status: status,
        comment: "Предложение продления до #{extension.proposed_ends_on.strftime('%d.%m.%Y')} снято")
    end
  end

  private

  def sick_period_is_full_days
    return unless sick_leave? && dates_supported?
    errors.add(:base, "Больничный учитывается только полными календарными днями (00:00–24:00)") unless full_calendar_days?
  end

  def sick_closure_is_unchanged
    return if @changing_sick_period
    if will_save_change_to_sick_closed_on? || will_save_change_to_sick_closed_at?
      errors.add(:base, "Закрытие больничного оформляется отдельным действием")
    end
  end
end
