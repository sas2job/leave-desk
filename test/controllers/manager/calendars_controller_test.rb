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

      get manager_calendar_path(year: 2026)

      assert_response :success
      assert_select "body", text: /Example User/
      assert_select "td.leave", minimum: 3
      assert_select "td.birthday", text: "ДР"
    end

    test "employee cannot open manager calendar" do
      sign_in_as(@employee)
      get manager_calendar_path
      assert_response :forbidden
    end

    private

    def create_user(email_address, role: :employee, manager: nil, birthday_on: nil)
      User.create!(name: "Example User", email_address:, password: "test-password",
        role:, manager:, birthday_on:)
    end
  end
end
