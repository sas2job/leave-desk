require "test_helper"

class LeaveRequestEventTest < ActiveSupport::TestCase
  test "event cannot be changed or deleted" do
    employee = User.create!(name: "Employee", email_address: "employee@example.test", password: "test-password")
    leave_type = LeaveType.create!(name: "Annual", code: "ANNUAL")
    request = LeaveRequest.create!(employee:, leave_type:, starts_on: Date.new(2026, 12, 1), ends_on: Date.new(2026, 12, 2))
    event = request.events.first

    assert_not event.update(comment: "changed")
    assert_not event.destroy
  end
end
