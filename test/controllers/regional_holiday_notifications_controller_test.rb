require "test_helper"

class RegionalHolidayNotificationsControllerTest < ActionDispatch::IntegrationTest
  test "employee sees and marks a regional holiday notification as read" do
    region = Region.create!(code: "RU-TA", name: "Республика Татарстан")
    employee = User.create!(name: "Employee", email_address: "holiday-notification@example.test",
      password: "test-password", region:)
    notification = Notification.create!(recipient: employee, region:, holiday_on: Date.new(2026, 11, 6))
    sign_in_as(employee)

    get notifications_path

    assert_response :success
    assert_select "##{dom_id(notification)}", text: /Региональный выходной: Республика Татарстан/
    assert_select "##{dom_id(notification)}", text: /06.11.2026/
    assert_select "a[href='#{calendar_path(year: 2026, month: 11)}']"

    patch notification_path(notification)

    assert_redirected_to notifications_path
    assert_predicate notification.reload, :read_at?
  end
end
