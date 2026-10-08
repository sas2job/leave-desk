class User < ApplicationRecord
  enum :role, { employee: 0, manager: 1, administrator: 2 }

  belongs_to :manager, class_name: "User", optional: true
  has_many :direct_reports, class_name: "User", foreign_key: :manager_id,
    inverse_of: :manager, dependent: :nullify
  has_many :leave_requests, foreign_key: :employee_id, inverse_of: :employee,
    dependent: :restrict_with_exception
  has_many :reviewed_leave_requests, class_name: "LeaveRequest",
    foreign_key: :reviewer_id, inverse_of: :reviewer,
    dependent: :restrict_with_exception

  normalizes :email_address, with: ->(email) { email.strip.downcase }

  validates :name, presence: true
  validates :email_address, presence: true, uniqueness: { case_sensitive: false },
    format: { with: URI::MailTo::EMAIL_REGEXP }
end
