require "test_helper"

class LeaveTypeTest < ActiveSupport::TestCase
  test "normalizes code" do
    leave_type = LeaveType.create!(name: "Annual leave", code: " annual ")

    assert_equal "ANNUAL", leave_type.code
  end

  test "holiday handling cannot change after leave type is used" do
    leave_type = LeaveType.create!(name: "Annual leave", code: "ANNUAL")
    employee = User.create!(name: "Employee", email_address: "employee@example.test",
      password: "test-password")
    LeaveRequest.create!(employee:, leave_type:, starts_on: Date.new(2026, 12, 1),
      ends_on: Date.new(2026, 12, 2))

    leave_type.holiday_handling = :exclude_public_holidays

    assert_not leave_type.valid?
    assert_includes leave_type.errors[:holiday_handling],
      "нельзя изменить для вида с существующими заявками"
  end
end
