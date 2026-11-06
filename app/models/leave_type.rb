class LeaveType < ApplicationRecord
  BIRTHDAY_CODE = "BIRTHDAY"
  SYSTEM_CODES = %w[ANNUAL BIRTHDAY MATERNITY CHILDCARE].freeze

  enum :holiday_handling, {
    include_public_holidays: 0,
    exclude_public_holidays: 1
  }, default: :include_public_holidays, validate: true

  has_many :leave_requests, dependent: :restrict_with_exception

  normalizes :code, with: ->(code) { code.strip.upcase }

  validates :name, :code, presence: true
  validates :name, length: { maximum: 100 }, if: :will_save_change_to_name?
  validates :code, length: { maximum: 40 }, if: :will_save_change_to_code?
  validates :code, uniqueness: true
  validate :active_has_boolean_input
  validate :birthday_code_is_unchanged
  validate :system_holiday_policy
  validate :holiday_handling_is_unchanged_when_used

  def save(**options)
    with_holiday_handling_lock { super }
  end

  def save!(**options)
    with_holiday_handling_lock { super }
  end

  def family_leave?
    %w[MATERNITY CHILDCARE].include?(code)
  end

  def statutory_leave?
    code == "ANNUAL" || family_leave?
  end

  def full_day_only?
    statutory_leave? || code == "BIRTHDAY"
  end

  private

  def with_holiday_handling_lock
    return yield unless persisted? && will_save_change_to_holiday_handling?

    self.class.transaction do
      self.class.uncached { self.class.where(id:).lock("FOR UPDATE").first }
      yield
    end
  end

  def active_has_boolean_input
    raw_active = attribute_before_type_cast("active")
    return if [ true, false, 1, 0, "1", "0", "true", "false" ].include?(raw_active)

    errors.add(:active, "должна быть указана как да или нет")
  end

  def birthday_code_is_unchanged
    return unless persisted? && will_save_change_to_code?
    return unless SYSTEM_CODES.include?(code_in_database) ||
      (SYSTEM_CODES.include?(code) && leave_requests.exists?)

    errors.add(:code, "нельзя изменить для системного вида отпуска")
  end

  def system_holiday_policy
    return unless new_record? || will_save_change_to_holiday_handling? || will_save_change_to_code?
    if code == "ANNUAL" && !exclude_public_holidays?
      errors.add(:holiday_handling, "для ежегодного отпуска праздники обязательно исключаются")
    elsif family_leave? && !include_public_holidays?
      errors.add(:holiday_handling, "семейный отпуск включает все календарные даты")
    end
  end

  def holiday_handling_is_unchanged_when_used
    return unless persisted? && will_save_change_to_holiday_handling?
    return unless self.class.uncached { leave_requests.exists? }

    errors.add(:holiday_handling, "нельзя изменить для вида с существующими заявками")
  end
end
