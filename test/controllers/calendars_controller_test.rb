require "test_helper"

class CalendarsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @manager = create_user("manager@example.test", role: :manager)
    @employee = create_user("employee@example.test", manager: @manager,
      birthday_on: Date.new(1990, 10, 9))
    @other_employee = create_user("other@example.test", manager: @manager)
    @leave_type = LeaveType.create!(name: "Ежегодный отпуск", code: "ANNUAL")
  end

  test "shows only the current user's pending and approved requests" do
    approved_request = create_request(@employee, starts_on: Date.new(2026, 10, 10))
    approved_request.approve!(by: @manager)
    create_request(@employee, starts_on: Date.new(2026, 10, 15))
    other_request = create_request(@other_employee, starts_on: Date.new(2026, 10, 20))
    other_request.approve!(by: @manager)
    sign_in_as(@employee)

    travel_to Date.new(2026, 10, 9) do
      get calendar_path
    end

    assert_response :success
    assert_select "h1", text: "Мой календарь — октябрь 2026"
    assert_select ".team-calendar td.leave", count: 2
    assert_select ".team-calendar td.leave-pending", count: 2
    assert_select ".team-calendar td.birthday", text: "ДР"
    assert_select "tbody th", count: 1
    assert_select "a[href='#{calendar_path}']", text: "Мой календарь"
    assert_select "summary", text: "Календари", count: 0
    assert_select "body", text: /other@example\.test/, count: 0
  end

  test "shows only visible dates for a request spanning the supported range" do
    request = LeaveRequest.create!(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2000, 1, 1), ends_on: Date.new(2100, 12, 31))
    request.approve!(by: @manager)
    sign_in_as(@employee)

    get calendar_path(year: 2026, month: 10)

    assert_response :success
    assert_select ".team-calendar td.leave", count: 31
  end

  private

  def create_user(email_address, role: :employee, manager: nil, birthday_on: nil)
    User.create!(name: "Example User", email_address:, password: "test-password",
      role:, manager:, birthday_on:)
  end

  def create_request(employee, starts_on:)
    LeaveRequest.create!(employee:, leave_type: @leave_type, starts_on:,
      ends_on: starts_on + 1.day)
  end
end
