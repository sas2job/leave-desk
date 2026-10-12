require "test_helper"

class SensitiveParameterFilteringTest < ActionDispatch::IntegrationTest
  test "successful and failed employee submissions filter personal data" do
    administrator = User.create!(name: "Administrator", email_address: "admin@example.test",
      password: "test-password", role: :administrator)
    sign_in_as(administrator)

    2.times do |attempt|
      post admin_users_path, params: { user: {
        name: "SYNTHETIC_PERSON_NAME", birthday_on: "1990-05-04",
        email_address: attempt.zero? ? "new@example.test" : administrator.email_address,
        password: "test-password", role: "employee", active: true
      } }

      assert_response attempt.zero? ? :redirect : :unprocessable_entity
      assert_equal "[FILTERED]", request.filtered_parameters.dig("user", "name")
      assert_equal "[FILTERED]", request.filtered_parameters.dig("user", "birthday_on")
      assert_equal "[FILTERED]", request.filtered_parameters.dig("user", "email_address")
    end
  end

  test "successful and failed leave submissions filter employee comments" do
    employee = User.create!(name: "Employee", email_address: "employee@example.test",
      password: "test-password")
    leave_type = LeaveType.create!(name: "Annual leave", code: "TEST_ANNUAL")
    sign_in_as(employee)

    [ [ "2026-11-01", "2026-11-02", :redirect ],
      [ "2026-11-04", "2026-11-03", :unprocessable_entity ] ].each do |start_date, end_date, status|
      post leave_requests_path, params: { leave_request: {
        leave_type_id: leave_type.id, starts_on: start_date, ends_on: end_date,
        employee_comment: "SYNTHETIC_PRIVATE_COMMENT"
      } }

      assert_response status
      assert_equal "[FILTERED]", request.filtered_parameters.dig("leave_request", "employee_comment")
    end
  end

  test "review submissions filter manager comments" do
    manager = User.create!(name: "Manager", email_address: "manager@example.test",
      password: "test-password", role: :manager)
    employee = User.create!(name: "Employee", email_address: "employee@example.test",
      password: "test-password", manager:)
    leave_type = LeaveType.create!(name: "Annual leave", code: "TEST_ANNUAL")
    leave_request = LeaveRequest.create!(employee:, leave_type:,
      starts_on: Date.new(2026, 11, 1), ends_on: Date.new(2026, 11, 2))
    sign_in_as(manager)

    patch approve_manager_leave_request_path(leave_request),
      params: { review_comment: "SYNTHETIC_REVIEW_COMMENT" }

    assert_redirected_to manager_leave_requests_path
    assert_equal "[FILTERED]", request.filtered_parameters["review_comment"]
  end
end
