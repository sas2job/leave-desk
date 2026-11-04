class Notification < ApplicationRecord
  belongs_to :recipient, class_name: "User"
  belongs_to :leave_request_event, optional: true
  belongs_to :region, optional: true
  has_one :leave_request, through: :leave_request_event
  scope :unread, -> { where(read_at: nil) }

  validate :exactly_one_source

  def regional_holiday?
    region_id.present?
  end

  def mark_as_read!
    update!(read_at: Time.current) unless read_at?
  end

  private

  def exactly_one_source
    request_event = leave_request_event_id.present?
    regional_holiday = region_id.present? && holiday_on.present?
    return if request_event != regional_holiday && (region_id.nil? == holiday_on.nil?)

    errors.add(:base, "Уведомление должно относиться к событию заявки или региональному выходному")
  end
end
