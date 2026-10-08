class LeaveRequest < ApplicationRecord
  class InvalidTransition < StandardError; end

  enum :status, { pending: 0, approved: 1, rejected: 2, cancelled: 3 }

  belongs_to :employee, class_name: "User", inverse_of: :leave_requests
  belongs_to :leave_type
  belongs_to :reviewer, class_name: "User", inverse_of: :reviewed_leave_requests,
    optional: true

  validates :starts_on, :ends_on, presence: true
  validate :ends_on_is_not_before_starts_on
  validate :reviewer_is_not_employee
  validate :leave_type_is_active, on: :create

  def approve!(by:, comment: nil)
    review!(new_status: :approved, by:, comment:)
  end

  def reject!(by:, comment: nil)
    review!(new_status: :rejected, by:, comment:)
  end

  def cancel!
    with_lock do
      raise InvalidTransition, "only pending or approved requests can be cancelled" unless pending? || approved?

      update!(status: :cancelled)
    end
  end

  private

  def review!(new_status:, by:, comment:)
    with_lock do
      raise InvalidTransition, "only pending requests can be reviewed" unless pending?
      raise InvalidTransition, "employees cannot review their own requests" if by == employee

      update!(status: new_status, reviewer: by, reviewed_at: Time.current,
        review_comment: comment)
    end
  end

  def ends_on_is_not_before_starts_on
    return if starts_on.blank? || ends_on.blank? || ends_on >= starts_on

    errors.add(:ends_on, "must be on or after the start date")
  end

  def reviewer_is_not_employee
    errors.add(:reviewer, "cannot review their own request") if reviewer == employee
  end

  def leave_type_is_active
    errors.add(:leave_type, "must be active") if leave_type && !leave_type.active?
  end
end
