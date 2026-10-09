require "test_helper"

class LeaveRequestTest < ActiveSupport::TestCase
  setup do
    @manager = User.create!(name: "Review Manager", email_address: "manager@example.test",
      password: "test-password", role: :manager)
    @employee = User.create!(name: "Example Employee", email_address: "employee@example.test",
      password: "test-password", manager: @manager)
    @leave_type = LeaveType.create!(name: "Annual leave", code: "annual")
  end

  test "new requests are pending" do
    request = create_request

    assert_predicate request, :pending?
  end

  test "end date cannot precede start date" do
    request = LeaveRequest.new(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 10, 10), ends_on: Date.new(2026, 10, 9))

    assert_not request.valid?
    assert_includes request.errors[:ends_on], "must be on or after the start date"
  end

  test "inactive leave type cannot be requested" do
    @leave_type.update!(active: false)

    request = LeaveRequest.new(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 10, 10), ends_on: Date.new(2026, 10, 10))

    assert_not request.valid?
    assert_includes request.errors[:leave_type], "must be active"
  end

  test "manager can approve a pending request" do
    request = create_request

    request.approve!(by: @manager, comment: "Coverage arranged")

    assert_predicate request, :approved?
    assert_equal @manager, request.reviewer
    assert_equal "Coverage arranged", request.review_comment
    assert_not_nil request.reviewed_at
  end

  test "employee cannot approve their own request" do
    request = create_request

    error = assert_raises(LeaveRequest::InvalidTransition) do
      request.approve!(by: @employee)
    end

    assert_equal "employees cannot review their own requests", error.message
    assert_predicate request.reload, :pending?
  end

  test "reviewed request cannot be reviewed again" do
    request = create_request
    request.reject!(by: @manager)

    assert_raises(LeaveRequest::InvalidTransition) do
      request.approve!(by: @manager)
    end
    assert_predicate request.reload, :rejected?
  end

  test "approved request can be cancelled" do
    request = create_request
    request.approve!(by: @manager)

    request.cancel!

    assert_predicate request, :cancelled?
  end

  test "active requests cannot overlap including period boundaries" do
    create_request
    request = LeaveRequest.new(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 10, 14), ends_on: Date.new(2026, 10, 16))

    assert_not request.valid?
    assert_includes request.errors[:base], "Период пересекается с другой активной заявкой"
  end

  test "cancelled request does not block same period" do
    existing_request = create_request
    existing_request.cancel!

    request = LeaveRequest.new(employee: @employee, leave_type: @leave_type,
      starts_on: existing_request.starts_on, ends_on: existing_request.ends_on)

    assert request.valid?
  end

  test "rejected request does not block same period" do
    existing_request = create_request
    existing_request.reject!(by: @manager)

    request = LeaveRequest.new(employee: @employee, leave_type: @leave_type,
      starts_on: existing_request.starts_on, ends_on: existing_request.ends_on)

    assert request.valid?
  end

  test "database prevents overlapping active requests" do
    existing_request = create_request

    assert_raises(ActiveRecord::StatementInvalid) do
      LeaveRequest.insert_all!([ {
        employee_id: @employee.id, leave_type_id: @leave_type.id,
        starts_on: existing_request.ends_on, ends_on: existing_request.ends_on + 2.days,
        status: LeaveRequest.statuses.fetch(:pending), created_at: Time.current,
        updated_at: Time.current
      } ])
    end
  end

  test "duration includes ordinary weekends" do
    request = LeaveRequest.new(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 10, 5), ends_on: Date.new(2026, 10, 11))

    assert_equal 7, request.duration_in_days
  end

  test "duration excludes federal holidays when leave type requires it" do
    @leave_type.update!(holiday_handling: :exclude_public_holidays)
    request = LeaveRequest.new(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 1, 1), ends_on: Date.new(2026, 1, 10))

    assert_equal 2, request.duration_in_days
  end

  test "duration includes federal holidays when leave type requires it" do
    request = LeaveRequest.new(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 1, 1), ends_on: Date.new(2026, 1, 10))

    assert_equal 10, request.duration_in_days
  end

  private

  def create_request
    LeaveRequest.create!(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 10, 12), ends_on: Date.new(2026, 10, 14))
  end
end
