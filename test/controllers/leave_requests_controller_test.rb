require "test_helper"

class LeaveRequestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @employee = create_user("employee@example.test")
    @other_employee = create_user("other@example.test")
    @leave_type = LeaveType.create!(name: "Annual leave", code: "TEST_ANNUAL")
    sign_in_as(@employee)
  end

  test "lists only current user requests" do
    own_request = create_request(@employee)
    other_request = create_request(@other_employee,
      starts_on: Date.new(2026, 12, 1))

    get leave_requests_path

    assert_response :success
    assert_select "body", text: /01\.11\.2026/
    assert_select "summary", text: "История заявки"
    assert_select "strong", text: "Заявка создана"
    assert_select "body", text: /\d{2} [а-яё.]+ \d{2}:\d{2}/i
    assert_no_match(/\d{2} [A-Z][a-z]{2} \d{2}:\d{2}/, response.body)
    assert_select "##{dom_id(own_request)}"
    assert_select "##{dom_id(other_request)}", count: 0
    assert_no_match(/01\.12\.2026/, response.body)
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

  test "rejects non-finite dates without a server error" do
    assert_no_difference("@employee.leave_requests.count") do
      post leave_requests_path, params: { leave_request: {
        leave_type_id: @leave_type.id, starts_on: "infinity", ends_on: "infinity"
      } }
    end

    assert_response :unprocessable_entity
    assert_select ".error-summary", text: /01\.01\.2000/
  end

  test "does not create overlapping request" do
    create_request(@employee)

    assert_no_difference("@employee.leave_requests.count") do
      post leave_requests_path, params: {
        leave_request: {
          leave_type_id: @leave_type.id,
          starts_on: "2026-11-02",
          ends_on: "2026-11-04"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select ".error-summary", text: /Период пересекается/
  end

  test "cancels own request" do
    manager = create_user("manager@example.test")
    manager.update!(role: :manager)
    @employee.update!(manager:)
    leave_request = create_request(@employee)

    delete leave_request_path(leave_request)

    assert_redirected_to leave_requests_path
    assert_predicate leave_request.reload, :cancelled?
    assert_equal "cancelled", manager.notifications.last.leave_request_event.event_type
  end

  test "shows date order validation in Russian without English field name" do
    post leave_requests_path, params: {
      leave_request: {
        leave_type_id: @leave_type.id,
        starts_on: "2026-11-14",
        ends_on: "2026-11-13"
      }
    }

    assert_response :unprocessable_entity
    assert_select ".error-summary", text: /Дата окончания не может быть раньше даты начала/
    assert_select ".error-summary", text: /Ends on/, count: 0
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

  def create_request(employee, starts_on: Date.new(2026, 11, 1))
    LeaveRequest.create!(employee:, leave_type: @leave_type,
      starts_on:, ends_on: starts_on + 1.day)
  end
end
