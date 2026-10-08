class LeaveType < ApplicationRecord
  has_many :leave_requests, dependent: :restrict_with_exception

  normalizes :code, with: ->(code) { code.strip.upcase }

  validates :name, :code, presence: true
  validates :code, uniqueness: true
end
