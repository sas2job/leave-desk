require "test_helper"

class LeaveRequestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @employee = create_user("employee@example.test")
    @other_employee = create_user("other@example.test")
    @leave_type = LeaveType.create!(name: "Annual leave", code: "ANNUAL")
    sign_in_as(@employee)
  end

  test "lists only current user requests" do
    own_request = create_request(@employee)
    other_request = create_request(@other_employee)

    get leave_requests_path

    assert_response :success
    assert_select "body", text: /#{own_request.starts_on}/
    assert_select "body", text: /#{Regexp.escape(other_request.starts_on.to_s)}/, count: 0
  end

  test "creates request for current user" do
    assert_difference("@employee.leave_requests.count", 1) do
      post leave_requests_path, params: {
        leave_request: {
          employee_id: @other_employee.id,
          leave_type_id: @leave_type.id,
          starts_on: "2026-11-10",
          ends_on: "2026-11-12",
          employee_comment: "Family plans"
        }
      }
    end

    assert_redirected_to leave_requests_path
    assert_equal @employee, LeaveRequest.order(:id).last.employee
  end

  test "cancels own request" do
    leave_request = create_request(@employee)

    delete leave_request_path(leave_request)

    assert_redirected_to leave_requests_path
    assert_predicate leave_request.reload, :cancelled?
  end

  test "cannot cancel another user request" do
    leave_request = create_request(@other_employee)

    delete leave_request_path(leave_request)

    assert_response :not_found
    assert_predicate leave_request.reload, :pending?
  end

  private

  def create_user(email_address)
    User.create!(name: "Example User", email_address:, password: "test-password")
  end

  def create_request(employee)
    LeaveRequest.create!(employee:, leave_type: @leave_type,
      starts_on: Date.new(2026, 11, 1), ends_on: Date.new(2026, 11, 2))
  end
end
