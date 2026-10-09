class User < ApplicationRecord
  has_secure_password

  enum :role, { employee: 0, manager: 1, administrator: 2 }

  belongs_to :manager, class_name: "User", optional: true
  has_many :direct_reports, class_name: "User", foreign_key: :manager_id,
    inverse_of: :manager, dependent: :nullify
  has_many :leave_requests, foreign_key: :employee_id, inverse_of: :employee,
    dependent: :restrict_with_exception
  has_many :reviewed_leave_requests, class_name: "LeaveRequest",
    foreign_key: :reviewer_id, inverse_of: :reviewer,
    dependent: :restrict_with_exception
  has_many :sessions, dependent: :destroy
  has_many :notifications, foreign_key: :recipient_id, dependent: :destroy

  normalizes :email_address, with: ->(email) { email.strip.downcase }

  validates :name, presence: true
  validates :email_address, presence: true, uniqueness: { case_sensitive: false },
    format: { with: URI::MailTo::EMAIL_REGEXP }
  validate :manager_is_active_manager
  validate :role_and_activity_support_direct_reports

  private

  def manager_is_active_manager
    return if manager.nil?

    errors.add(:manager, "не может совпадать с сотрудником") if manager == self
    unless manager.active? && manager.manager?
      errors.add(:manager, "должен быть активным руководителем")
    end
  end

  def role_and_activity_support_direct_reports
    return unless persisted? && direct_reports.exists?
    return if manager? && active?

    errors.add(:role, "нельзя изменить, пока у пользователя есть подчинённые") unless manager?
    errors.add(:active, "нельзя отключить, пока у пользователя есть подчинённые") unless active?
  end
end
