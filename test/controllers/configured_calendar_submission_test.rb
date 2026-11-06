require "test_helper"

class ConfiguredCalendarSubmissionTest < ActionDispatch::IntegrationTest
  include StatutoryLeaveTestHelper
  setup do
    prepare_statutory_scenario
    sign_in_as(@employee)
  end

  test "every year of a cross year employee submission must be configured" do
    assert_no_difference([ "LeaveRequest.count", "LeaveRequestEvent.count", "Notification.count" ]) do
      post leave_requests_path, params: { leave_request: {
        leave_type_id: @annual.id, starts_on: "2028-12-30", ends_on: "2029-01-10", full_day: "1"
      } }, as: :json
      assert_response :unprocessable_entity
      assert_includes response.parsed_body.fetch("errors").join, "2029"
    end
  end

  test "public input cannot opt out of required calendar coverage" do
    assert_no_difference("LeaveRequest.count") do
      post leave_requests_path, params: { leave_request: {
        leave_type_id: @annual.id, starts_on: "2029-01-01", ends_on: "2029-01-10",
        require_marked_calendars: false
      } }, as: :json
      assert_response :bad_request
    end
  end
end
