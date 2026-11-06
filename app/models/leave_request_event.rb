class LeaveRequestEvent < ApplicationRecord
  enum :event_type, { created: 0, approved: 1, rejected: 2, cancelled: 3,
    calendar_unverified: 4, calendar_reconciled: 5,
    recall_proposed: 6, recall_consented: 7, recall_declined: 8, recall_withdrawn: 9, recalled: 10,
    statutory_registered: 11, childcare_returned: 12, statutory_clarification: 13 }
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
    if created? && leave_request.family_leave? || childcare_returned?
      recipient_ids = User.administrator.where(active: true).pluck(:id)
      recipient_ids << leave_request.employee.manager_id if childcare_returned?
      recipient_ids.compact.uniq.each { |id| notifications.create!(recipient_id: id) }
      return
    end
    if calendar_unverified?
      User.administrator.where(active: true).find_each do |administrator|
        notifications.create!(recipient: administrator)
      end
      return
    end

    recipient = case event_type
    when "created", "cancelled", "recall_consented", "recall_declined" then leave_request.employee.manager
    when "approved", "rejected", "calendar_reconciled", "recall_proposed", "recalled", "statutory_registered", "statutory_clarification" then leave_request.employee
    when "recall_withdrawn"
      actor_id == leave_request.employee_id ? leave_request.employee.manager : leave_request.employee
    end
    notifications.create!(recipient:) if recipient
  end
end
