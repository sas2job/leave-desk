class LeaveRequest < ApplicationRecord
  class InvalidTransition < StandardError; end

  enum :status, { pending: 0, approved: 1, rejected: 2, cancelled: 3 }
  enum :day_part, { full_day: 0, morning: 1, afternoon: 2 }, default: :full_day

  belongs_to :employee, class_name: "User", inverse_of: :leave_requests
  belongs_to :leave_type
  belongs_to :reviewer, class_name: "User", inverse_of: :reviewed_leave_requests,
    optional: true

  validates :starts_on, :ends_on, presence: true
  validate :ends_on_is_not_before_starts_on
  validate :reviewer_is_not_employee
  validate :leave_type_is_active, on: :create
  validate :period_does_not_overlap_active_request
  validate :partial_day_is_single_day

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

  def duration_in_days
    return if leave_type.blank? || starts_on.blank? || ends_on.blank? || ends_on < starts_on

    days = (starts_on..ends_on).count do |date|
      leave_type.include_public_holidays? || !RussianFederalHoliday.on?(date)
    end
    full_day? ? days : days * 0.5
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

  def period_does_not_overlap_active_request
    return if employee_id.blank? || starts_on.blank? || ends_on.blank?
    return unless pending? || approved?

    overlapping_request = self.class.where(employee_id:, status: %i[pending approved])
      .where.not(id:).where("starts_on <= ? AND ends_on >= ?", ends_on, starts_on)
      .any? { |request| time_slots_overlap?(request) }
    errors.add(:base, "Период пересекается с другой активной заявкой") if overlapping_request
  end

  def partial_day_is_single_day
    return if full_day? || starts_on.blank? || ends_on.blank? || starts_on == ends_on

    errors.add(:day_part, "можно выбрать только для заявки на одну дату")
  end

  def time_slots_overlap?(other)
    return true unless starts_on == ends_on && other.starts_on == other.ends_on
    return true if full_day? || other.full_day?

    day_part == other.day_part
  end
end
