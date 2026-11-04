require "test_helper"

class RegionalHolidayNotifierTest < ActiveSupport::TestCase
  setup do
    @region = Region.create!(code: "RU-TA", name: "Республика Татарстан")
    @tatarstan_employee = User.create!(name: "Tatarstan Employee", email_address: "holiday-ta@example.test",
      password: "test-password", city: "Казань", region: @region)
    @other_employee = User.create!(name: "Other Employee", email_address: "holiday-other@example.test",
      password: "test-password", city: "Москва")
    RegionalCalendar.create!(region: @region, year: 2026, legal_basis: "Закон Республики Татарстан", complete: true,
      public_holidays: [ Date.new(2026, 11, 6) ],
      additional_days_off: [ Date.new(2026, 11, 9) ])
  end

  test "notifies only active employees in the matching region on the preceding morning" do
    morning = Time.find_zone!("Europe/Moscow").local(2026, 11, 5, 9, 5)
    inactive_employee = User.create!(name: "Inactive Employee", email_address: "holiday-inactive@example.test",
      password: "test-password", city: "Казань", region: @region, active: false)

    assert_difference("Notification.count", 1) { RegionalHolidayNotifier.deliver_due!(at: morning) }
    notification = @tatarstan_employee.notifications.last
    assert notification.regional_holiday?
    assert_equal @region, notification.region
    assert_equal Date.new(2026, 11, 6), notification.holiday_on
    assert_empty @other_employee.notifications
    assert_empty inactive_employee.notifications
    assert_no_difference("Notification.count") { RegionalHolidayNotifier.deliver_due!(at: morning + 1.hour) }
  end

  test "additional day off is notified, but not before the preceding day" do
    before = Time.find_zone!("Europe/Moscow").local(2026, 11, 7, 9, 5)
    morning = before + 1.day

    assert_no_difference("Notification.count") { RegionalHolidayNotifier.deliver_due!(at: before) }
    assert_difference("Notification.count", 1) { RegionalHolidayNotifier.deliver_due!(at: morning) }
    assert_equal Date.new(2026, 11, 9), @tatarstan_employee.notifications.last.holiday_on
  end

  test "notifications use the employee's local morning" do
    @tatarstan_employee.update!(city: "Казань")
    far_east_employee = User.create!(name: "Far East Employee", email_address: "holiday-east@example.test",
      password: "test-password", city: "Владивосток", region: @region)
    morning_in_far_east = Time.find_zone!("Asia/Vladivostok").local(2026, 11, 5, 9, 5)

    RegionalHolidayNotifier.deliver_due!(at: morning_in_far_east)

    assert_equal 1, far_east_employee.notifications.count
    assert_empty @tatarstan_employee.notifications
  end

  test "regional notification does not require a leave request event" do
    morning = Time.find_zone!("Europe/Moscow").local(2026, 11, 5, 9, 5)
    RegionalHolidayNotifier.deliver_due!(at: morning)

    assert_nil @tatarstan_employee.notifications.last.leave_request_event_id
  end
end
