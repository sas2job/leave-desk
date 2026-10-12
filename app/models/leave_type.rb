class LeaveType < ApplicationRecord
  enum :holiday_handling, {
    include_public_holidays: 0,
    exclude_public_holidays: 1
  }, default: :include_public_holidays, validate: true

  has_many :leave_requests, dependent: :restrict_with_exception

  normalizes :code, with: ->(code) { code.strip.upcase }

  validates :name, :code, presence: true
  validates :code, uniqueness: true
  validate :active_has_boolean_input
  validate :holiday_handling_is_unchanged_when_used

  private

  def active_has_boolean_input
    raw_active = attribute_before_type_cast("active")
    return if [ true, false, 1, 0, "1", "0", "true", "false" ].include?(raw_active)

    errors.add(:active, "должна быть указана как да или нет")
  end

  def holiday_handling_is_unchanged_when_used
    return unless persisted? && will_save_change_to_holiday_handling?
    return unless leave_requests.exists?

    errors.add(:holiday_handling, "нельзя изменить для вида с существующими заявками")
  end
end
