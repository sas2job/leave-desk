require "test_helper"

module Manager
  class LeaveRequestsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @manager = create_user("manager@example.test", role: :manager)
      @other_manager = create_user("other-manager@example.test", role: :manager)
      @employee = create_user("employee@example.test", manager: @manager)
      @other_employee = create_user("other@example.test", manager: @other_manager)
      @leave_type = LeaveType.create!(name: "Annual leave", code: "ANNUAL")
    end

    test "manager lists only direct report requests" do
      managed_request = create_request(@employee, starts_on: Date.new(2026, 11, 1))
      other_request = create_request(@other_employee, starts_on: Date.new(2026, 12, 1))
      sign_in_as(@manager)

      get manager_leave_requests_path

      assert_response :success
      assert_select "body", text: /01\.11\.2026/
    assert_select "summary", text: "История заявки"
      assert_select "body", text: /#{Regexp.escape(other_request.starts_on.strftime("%d.%m.%Y"))}/, count: 0
    end

    test "manager approves direct report request" do
      leave_request = create_request(@employee)
      sign_in_as(@manager)

      patch approve_manager_leave_request_path(leave_request),
        params: { review_comment: "Approved" }

      assert_redirected_to manager_leave_requests_path
      assert_predicate leave_request.reload, :approved?
      assert_equal @manager, leave_request.reviewer
    end

    test "manager cannot review another manager direct report" do
      leave_request = create_request(@other_employee)
      sign_in_as(@manager)

      patch approve_manager_leave_request_path(leave_request)

      assert_response :not_found
      assert_predicate leave_request.reload, :pending?
    end

    test "employee cannot open manager queue" do
      sign_in_as(@employee)

      get manager_leave_requests_path

      assert_response :forbidden
    end

    private

    def create_user(email_address, role: :employee, manager: nil)
      User.create!(name: "Example User", email_address:, password: "test-password",
        role:, manager:)
    end

    def create_request(employee, starts_on: Date.new(2026, 11, 1))
      LeaveRequest.create!(employee:, leave_type: @leave_type, starts_on:,
        ends_on: starts_on + 1.day)
    end
  end
end
