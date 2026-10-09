require "test_helper"

class NotificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @manager = User.create!(name: "Manager", email_address: "manager@example.test",
      password: "test-password", role: :manager)
    @employee = User.create!(name: "Employee", email_address: "employee@example.test",
      password: "test-password", manager: @manager)
    leave_type = LeaveType.create!(name: "Annual", code: "ANNUAL")
    @leave_request = LeaveRequest.create!(employee: @employee, leave_type:,
      starts_on: Date.new(2026, 12, 1), ends_on: Date.new(2026, 12, 2))
  end

  test "manager sees and reads own notification" do
    sign_in_as(@manager)
    notification = @manager.notifications.first
    get notifications_path
    assert_response :success
    assert_select "body", text: /Заявка создана/
    assert_select "a[href='#{manager_leave_requests_path(anchor: "leave_request_#{@leave_request.id}")}']",
      text: "Заявка создана"
    get manager_leave_requests_path(anchor: "leave_request_#{@leave_request.id}")
    assert_response :success
    assert_select "#leave_request_#{@leave_request.id}"
    patch notification_path(notification)
    assert_redirected_to notifications_path
    assert notification.reload.read_at?
  end

  test "employee cannot read manager notification" do
    sign_in_as(@employee)
    patch notification_path(@manager.notifications.first)
    assert_response :not_found
  end
end
