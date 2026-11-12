class AnnualLeaveYear < ApplicationRecord
  belongs_to :employee, class_name: "User"
  belongs_to :recorded_by, class_name: "User"
  has_many :annual_leave_bookings, dependent: :restrict_with_exception
  has_many :annual_leave_adjustments, dependent: :restrict_with_exception
  attr_readonly :employee_id, :recorded_by_id, :starts_on, :ends_on, :basis
  attr_accessor :history_confirmed

  validates :basis, presence: true, length: { maximum: 200 }
  validates :entitlement_days, numericality: { only_integer: true, greater_than_or_equal_to: 28, less_than_or_equal_to: 1_000_000 }
  validates :opening_used_minutes, :reserved_minutes, :committed_minutes,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :history_confirmed, acceptance: { accept: true }, on: :create
  validate :period_is_valid
  validate :minimum_entitlement
  validate :capacity_is_valid
  validate :changes_are_explicit, on: :update
  before_destroy :retain_history

  def available_minutes
    entitlement_days.to_i * 1440 - opening_used_minutes.to_i - reserved_minutes.to_i - committed_minutes.to_i
  end

  def opening_used_days
    opening_used_minutes.to_i / 1440.0
  end

  def newly_used_minutes
    annual_leave_bookings.select(&:booking_committed?).sum do |booking|
      request = booking.leave_request
      ordered = request.annual_leave_bookings.includes(:annual_leave_year).sort_by { |item| [ item.annual_leave_year.starts_on, item.annual_leave_year_id ] }
      before = ordered.take_while { |item| item.id != booking.id }.sum(&:minutes)
      [ [ request.annual_used_minutes - before, 0 ].max, booking.minutes ].min
    end
  end

  def opening_used_days=(value)
    self.opening_used_minutes = if value.to_s.match?(/\A\d+(?:\.[05])?\z/)
      (BigDecimal(value.to_s) * 1440).to_i
    else
      -1
    end
  end

  def self.record!(employee:, by:, **attributes)
    employee.with_lock do
      require_editor!(employee:, by:)
      create!(employee:, recorded_by: by, **attributes)
    end
  end

  def revise!(by:, entitlement_days:, opening_used_days:, reason:)
    employee.with_lock do
      self.class.require_editor!(employee:, by:)
      lock!
      raise LeaveRequest::InvalidTransition, "Укажите основание корректировки до 200 символов" if reason.blank? || reason.length > 200
      previous_entitlement = self.entitlement_days
      previous_used = opening_used_minutes
      @revising = true
      assign_attributes(entitlement_days:, opening_used_days:)
      save!
      annual_leave_adjustments.create!(actor: by, reason:, previous_entitlement_days: previous_entitlement,
        entitlement_days: self.entitlement_days, previous_opening_used_minutes: previous_used, opening_used_minutes:)
    ensure
      @revising = false
    end
  end

  def self.require_editor!(employee:, by:)
    authorized = by&.active? && (by.administrator? || by.manager? && by.id != employee.id && employee.manager_id == by.id)
    raise LeaveRequest::ReviewNotAuthorized unless authorized
  end

  private

  def period_is_valid
    unless starts_on.is_a?(Date) && ends_on.is_a?(Date) && SupportedCalendarPeriod::DATES.cover?(starts_on) &&
        SupportedCalendarPeriod::DATES.cover?(ends_on) && ends_on > starts_on
      errors.add(:base, "Укажите допустимые границы рабочего года")
      return
    end
    if self.class.where(employee_id:).where.not(id:).where("starts_on <= ? AND ends_on >= ?", ends_on, starts_on).exists?
      errors.add(:base, "Рабочие годы одного сотрудника не могут пересекаться")
    end
  end

  def minimum_entitlement
    return unless new_record? || will_save_change_to_entitlement_days?
    return unless employee && starts_on.is_a?(Date)
    minimum = employee.annual_default_days(on: starts_on)
    errors.add(:entitlement_days, "не может быть меньше установленной продолжительности #{minimum} дн.") if entitlement_days.to_i < minimum
  end

  def capacity_is_valid
    errors.add(:base, "Нельзя уменьшить остаток ниже использованных и зарезервированных дней") if available_minutes.negative?
  end

  def changes_are_explicit
    return if @revising
    if will_save_change_to_entitlement_days? || will_save_change_to_opening_used_minutes?
      errors.add(:base, "Изменение остатка требует отдельной корректировки с основанием")
    end
  end

  def retain_history
    errors.add(:base, "История рабочих лет сохраняется")
    throw :abort
  end
end
