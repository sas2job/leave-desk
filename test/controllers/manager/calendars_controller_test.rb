require "test_helper"

module Manager
  class CalendarsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @manager = create_user("manager@example.test", role: :manager)
      @employee = create_user("employee@example.test", manager: @manager,
        birthday_on: Date.new(1990, 5, 12))
      @leave_type = LeaveType.create!(name: "Annual", code: "ANNUAL")
    end

    test "manager sees direct report annual calendar" do
      request = LeaveRequest.create!(employee: @employee, leave_type: @leave_type,
        starts_on: Date.new(2026, 6, 10), ends_on: Date.new(2026, 6, 12))
      request.approve!(by: @manager)
      sign_in_as(@manager)

  get manager_calendar_path(year: 2026, month: "all")

      assert_response :success
      assert_select "body", text: /Example User/
      assert_select "td.leave", minimum: 3
      assert_select "td.birthday", text: "ДР"
    end

    test "shows only visible dates for a long approved request" do
      request = LeaveRequest.create!(employee: @employee, leave_type: @leave_type,
        starts_on: Date.new(2000, 1, 1), ends_on: Date.new(2100, 12, 31))
      request.approve!(by: @manager)
      sign_in_as(@manager)

      get manager_calendar_path(year: 2026, month: 10)

      assert_response :success
      assert_select ".team-calendar td.leave", count: 31
    end

    test "defaults to the current month" do
      sign_in_as(@manager)

      travel_to Date.new(2026, 10, 9) do
        get manager_calendar_path
      end

      assert_response :success
      assert_select "h1", text: "Календарь октябрь 2026"
      assert_select ".team-calendar-wrap.team-calendar-wrap--month"
      assert_select "table.team-calendar.team-calendar--month"
      assert_select "tbody td", count: 31
    end

    test "employee cannot open manager calendar" do
      sign_in_as(@employee)
      get manager_calendar_path
      assert_response :forbidden
    end

    test "administrator sees all active employees in calendar" do
      administrator = create_user("admin@example.test", role: :administrator)
      create_user("other@example.test", name: "Other Employee", birthday_on: Date.new(1992, 10, 4))
      sign_in_as(administrator)

      get manager_calendar_path(year: 2026, month: 10)

      assert_response :success
      assert_select "tbody th", text: "Example User"
      assert_select "tbody th", text: "Other Employee"
      assert_select "details.site-nav__dropdown summary", text: "Календари"
      assert_select "a[href='#{manager_calendar_path}']", text: "Общий календарь"
      assert_select "a[href='#{calendar_path}']", text: "Мой календарь"
      assert_select "td.birthday", text: "ДР", count: 1
    end

    private

    def create_user(email_address, role: :employee, manager: nil, birthday_on: nil, name: "Example User")
      User.create!(name:, email_address:, password: "test-password",
        role:, manager:, birthday_on:)
    end
  end
end
