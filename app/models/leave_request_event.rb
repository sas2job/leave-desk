class LeaveRequestEvent < ApplicationRecord
  enum :event_type, { created: 0, approved: 1, rejected: 2, cancelled: 3 }
  belongs_to :leave_request
  belongs_to :actor, class_name: "User"
  validates :occurred_at, :to_status, presence: true
  before_update :prevent_change
  before_destroy :prevent_change

  private

  def prevent_change
    errors.add(:base, "События заявки нельзя изменять или удалять")
    throw :abort
  end
end
