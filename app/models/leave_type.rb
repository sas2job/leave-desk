class LeaveType < ApplicationRecord
  enum :holiday_handling, {
    include_public_holidays: 0,
    exclude_public_holidays: 1
  }, default: :include_public_holidays, validate: true

  has_many :leave_requests, dependent: :restrict_with_exception

  normalizes :code, with: ->(code) { code.strip.upcase }

  validates :name, :code, presence: true
  validates :code, uniqueness: true
  validate :holiday_handling_is_unchanged_when_used

  private

  def holiday_handling_is_unchanged_when_used
    return unless persisted? && will_save_change_to_holiday_handling?
    return unless leave_requests.exists?

    errors.add(:holiday_handling, "нельзя изменить для вида с существующими заявками")
  end
end
