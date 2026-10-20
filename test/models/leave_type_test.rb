require "test_helper"

class LeaveTypeTest < ActiveSupport::TestCase
  test "normalizes code" do
    leave_type = LeaveType.create!(name: "Annual leave", code: " test_annual ")

    assert_equal "TEST_ANNUAL", leave_type.code
  end

  test "birthday reference code cannot change" do
    leave_type = LeaveType.find_or_create_by!(code: "BIRTHDAY") do |new_type|
      new_type.name = "Birthday leave"
    end

    assert_not leave_type.update(code: "BDAY")
    assert_includes leave_type.errors[:code], "нельзя изменить для системного вида отпуска"
    assert_equal "BIRTHDAY", leave_type.reload.code
  end

  test "holiday handling cannot change after leave type is used" do
    leave_type = LeaveType.create!(name: "Annual leave", code: "TEST_ANNUAL")
    employee = User.create!(name: "Employee", email_address: "employee@example.test",
      password: "test-password")
    LeaveRequest.create!(employee:, leave_type:, starts_on: Date.new(2026, 12, 1),
      ends_on: Date.new(2026, 12, 2))

    leave_type.holiday_handling = :exclude_public_holidays

    assert_not leave_type.valid?
    assert_includes leave_type.errors[:holiday_handling],
      "нельзя изменить для вида с существующими заявками"
  end

  test "rejects an unknown holiday handling option" do
    leave_type = LeaveType.new(name: "Annual leave", code: "TEST_ANNUAL",
      holiday_handling: "unknown")

    assert_not leave_type.valid?
    assert_predicate leave_type.errors[:holiday_handling], :present?
  end
end
