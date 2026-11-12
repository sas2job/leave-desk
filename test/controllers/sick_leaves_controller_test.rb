require "test_helper"

class SickLeavesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @manager = User.create!(name: "Sick Manager", email_address: "sick-http-manager@example.test", password: "test-password", role: :manager)
    @employee = User.create!(name: "Sick Employee", email_address: "sick-http-employee@example.test", password: "test-password", manager: @manager)
    @outsider = User.create!(name: "Other", email_address: "sick-http-other@example.test", password: "test-password")
    @type = LeaveType.find_or_create_by!(code: "SICK") { |type| type.name = "Больничный" }
    @sick_request = LeaveRequest.create!(employee: @employee, leave_type: @type,
      starts_on: Date.new(2026, 10, 1), ends_on: Date.new(2026, 10, 10))
    @sick_request.approve!(by: @manager)
  end

  test "employee proposes manager confirms and employee closes through the same request" do
    sign_in_as(@employee)
    get leave_requests_path
    assert_select "body", text: /Требует уточнения/
    assert_select "input[name='sick_leave[proposed_ends_on]']"
    post leave_request_extend_sick_leave_path(@sick_request), params: { sick_leave: { proposed_ends_on: "2026-10-20" } }
    assert_response :redirect
    extension = @sick_request.sick_leave_extensions.sole
    assert_equal Date.new(2026, 10, 10), @sick_request.reload.ends_on

    sign_in_as(@manager)
    get manager_leave_requests_path
    assert_select "button", text: "Подтвердить продление"
    patch approve_manager_leave_request_sick_leave_extension_path(@sick_request, extension)
    assert_response :redirect
    assert_equal Date.new(2026, 10, 20), @sick_request.reload.ends_on

    sign_in_as(@employee)
    post leave_request_close_sick_leave_path(@sick_request), params: { sick_leave: { closed_on: "2026-10-14" } }
    assert_response :redirect
    assert_equal Date.new(2026, 10, 14), @sick_request.reload.sick_closed_on
    get leave_requests_path
    assert_select "body", text: /Больничный закрыт/
    assert_select "input[name='sick_leave[proposed_ends_on]']", count: 0
    assert_select "input[name='sick_leave[closed_on]']", count: 0
  end

  test "another employee cannot extend close or review requests" do
    sign_in_as(@outsider)
    assert_no_difference [ "SickLeaveExtension.count", "LeaveRequestEvent.count" ] do
      post leave_request_extend_sick_leave_path(@sick_request), params: { sick_leave: { proposed_ends_on: "2026-10-20" } }
      assert_response :not_found
      post leave_request_close_sick_leave_path(@sick_request), params: { sick_leave: { closed_on: "2026-10-10" } }
      assert_response :not_found
    end
    extension = SickLeaveExtension.propose!(leave_request: @sick_request, by: @employee, proposed_ends_on: Date.new(2026, 10, 20))
    patch approve_manager_leave_request_sick_leave_extension_path(@sick_request, extension)
    assert_response :forbidden
  end

  test "unrelated manager cannot review and rejects keep existing period" do
    extension = SickLeaveExtension.propose!(leave_request: @sick_request, by: @employee, proposed_ends_on: Date.new(2026, 10, 20))
    @outsider.update!(role: :manager)
    sign_in_as(@outsider)
    patch approve_manager_leave_request_sick_leave_extension_path(@sick_request, extension)
    assert_response :not_found
    assert_predicate extension.reload, :pending?
    sign_in_as(@manager)
    patch reject_manager_leave_request_sick_leave_extension_path(@sick_request, extension)
    assert_response :redirect
    assert_predicate extension.reload, :rejected?
    assert_equal Date.new(2026, 10, 10), @sick_request.reload.ends_on
  end

  test "malformed dates and structured parameters do not mutate requests" do
    sign_in_as(@employee)
    assert_no_difference "SickLeaveExtension.count" do
      [ "infinity", "2026-02-30", "2101-01-01", "2026-10-10" ].each do |date|
        post leave_request_extend_sick_leave_path(@sick_request), params: { sick_leave: { proposed_ends_on: date } }
        assert_response :redirect
        assert flash[:alert].present?
      end
      post leave_request_extend_sick_leave_path(@sick_request), params: { sick_leave: { proposed_ends_on: [ "2026-10-20" ] } }
      assert_response :bad_request
      post leave_request_extend_sick_leave_path(@sick_request), params: { sick_leave: { proposed_ends_on: "2026-10-20", status: "approved" } }
      assert_response :bad_request
    end
    assert_equal Date.new(2026, 10, 10), @sick_request.reload.ends_on
  end

  test "employee submits cross year sick leave without calendar data and cannot submit partial day" do
    sign_in_as(@employee)
    assert_difference "LeaveRequest.count", 1 do
      post leave_requests_path, params: { leave_request: { leave_type_id: @type.id,
        starts_on: "30.12.2025", ends_on: "02.01.2026", full_day: "1" } }
      assert_response :redirect
    end
    assert_no_difference "LeaveRequest.count" do
      post leave_requests_path, params: { leave_request: { leave_type_id: @type.id,
        starts_on: "20.10.2026", ends_on: "20.10.2026", start_time: "09:00", end_time: "12:00" } }
      assert_response :unprocessable_entity
      assert_select ".error-summary", text: /полными календарными днями/
    end
  end
end
