class LeaveRequestEvent < ApplicationRecord
  enum :event_type, { created: 0, approved: 1, rejected: 2, cancelled: 3 }
  belongs_to :leave_request
  belongs_to :actor, class_name: "User"
  has_one :notification, dependent: :destroy
  validates :occurred_at, :to_status, presence: true
  before_update :prevent_change
  before_destroy :prevent_change
  after_create :deliver_notification

  private

  def prevent_change
    errors.add(:base, "События заявки нельзя изменять или удалять")
    throw :abort
  end

  def deliver_notification
    recipient = case event_type
    when "created", "cancelled" then leave_request.employee.manager
    when "approved", "rejected" then leave_request.employee
    end
    create_notification!(recipient:) if recipient
  end
end
