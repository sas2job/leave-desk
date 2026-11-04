class Region < ApplicationRecord
  has_many :regional_calendars, dependent: :restrict_with_exception
  has_many :users, dependent: :restrict_with_exception
  has_many :leave_requests, dependent: :restrict_with_exception

  validates :code, presence: true, uniqueness: true,
    format: { with: /\ARU-[A-Z0-9]{2,3}\z/, message: "укажите в формате RU-TA" }
  validates :name, presence: true, length: { maximum: 100 }
  validate :code_is_unchanged, on: :update

  private

  def code_is_unchanged
    errors.add(:code, "нельзя изменить после создания региона") if will_save_change_to_code?
  end
end
