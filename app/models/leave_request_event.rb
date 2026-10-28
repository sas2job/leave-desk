class LeaveRequestEvent < ApplicationRecord
  enum :event_type, { created: 0, approved: 1, rejected: 2, cancelled: 3,
    calendar_unverified: 4, calendar_reconciled: 5 }
  belongs_to :leave_request
  belongs_to :actor, class_name: "User", optional: true
  has_many :notifications, dependent: :restrict_with_exception
  validates :occurred_at, :to_status, presence: true
  validates :comment, length: { maximum: LeaveRequest::COMMENT_MAX_LENGTH }
  validates :actor, presence: true, unless: :calendar_unverified?
  before_update :prevent_change
  before_destroy :prevent_change
  after_create :deliver_notification

  private

  def prevent_change
    errors.add(:base, "События заявки нельзя изменять или удалять")
    throw :abort
  end

  def deliver_notification
    if calendar_unverified?
      User.administrator.where(active: true).find_each do |administrator|
        notifications.create!(recipient: administrator)
      end
      return
    end

    recipient = case event_type
    when "created", "cancelled" then leave_request.employee.manager
    when "approved", "rejected", "calendar_reconciled" then leave_request.employee
    end
    notifications.create!(recipient:) if recipient
  end
end
