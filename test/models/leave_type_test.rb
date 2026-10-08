require "test_helper"

class LeaveTypeTest < ActiveSupport::TestCase
  test "normalizes code" do
    leave_type = LeaveType.create!(name: "Annual leave", code: " annual ")

    assert_equal "ANNUAL", leave_type.code
  end
end
