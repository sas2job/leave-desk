class Notification < ApplicationRecord
  belongs_to :recipient, class_name: "User"
  belongs_to :leave_request_event
  has_one :leave_request, through: :leave_request_event
  scope :unread, -> { where(read_at: nil) }

  def mark_as_read!
    update!(read_at: Time.current) unless read_at?
  end
end
