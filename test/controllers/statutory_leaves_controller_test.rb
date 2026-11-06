require "test_helper"

class StatutoryLeavesControllerTest < ActionDispatch::IntegrationTest
  include StatutoryLeaveTestHelper
  setup { prepare_statutory_scenario }

  test "worker requests cross year childcare and only another administrator registers documents" do
    sign_in_as(@employee)
    post leave_requests_path, params: { leave_request: childcare_attributes }
    assert_response :redirect
    assert_equal "[FILTERED]", request.filtered_parameters.dig("leave_request", "child_born_on")
    record = @employee.leave_requests.sole
    assert_predicate record, :pending?
    assert_equal @administrator, Notification.last.recipient
    sign_in_as(@manager)
    post register_admin_family_leave_path(record), params: { legal_review: family_review_attributes }
    assert_response :forbidden
    assert_no_difference([ "LeaveRequestEvent.count", "Notification.count" ]) do
      patch approve_manager_leave_request_path(record)
      assert_response :redirect
      patch reject_manager_leave_request_path(record)
      assert_response :redirect
    end
    sign_in_as(@administrator)
    get admin_family_leave_path(record)
    assert_select "form[action='#{register_admin_family_leave_path(record)}']"
    post register_admin_family_leave_path(record), params: { legal_review: family_review_attributes }
    assert_response :see_other
    assert_equal "[FILTERED]", request.filtered_parameters["legal_review"]
    assert_predicate record.reload, :approved?
  end

  test "maternity requires a covering document and clarification preserves pending state" do
    record = LeaveRequest.create!(employee: @employee, leave_type: @maternity,
      starts_on: Date.new(2026, 10, 1), ends_on: Date.new(2027, 2, 1))
    sign_in_as(@administrator)
    post register_admin_family_leave_path(record), params: { legal_review: family_review_attributes }
    assert_response :unprocessable_entity
    assert_predicate record.reload, :pending?
    post clarify_admin_family_leave_path(record), params: { review_comment: "Уточните реквизиты документа" }
    assert_response :see_other
    assert_predicate record.reload, :pending?
    assert_equal @employee, Notification.last.recipient
    post register_admin_family_leave_path(record), params: { legal_review: family_review_attributes.merge(
      document_starts_on: "2026-09-15", document_ends_on: "2027-02-01") }
    assert_response :see_other
    assert_predicate record.reload, :approved?
  end

  test "childcare return needs employee statement and resume keeps same child and owner" do
    record = create_childcare
    record.register_family!(by: @administrator, legal_review: family_review_attributes)
    sign_in_as(@employee)
    post return_from_childcare_leave_request_path(record), params: { childcare_return: {
      return_on: "2026-10-14", confirmed: "1"
    } }
    assert_response :see_other
    assert_predicate record.reload, :interrupted?
    get new_leave_request_path(resumes_request_id: record.id)
    assert_response :success
    assert_select "input[name='leave_request[resumes_request_id]'][value='#{record.id}']"
    post leave_requests_path, params: { leave_request: childcare_attributes.merge(
      starts_on: "2026-11-01", resumes_request_id: record.id) }
    assert_response :redirect
    assert_equal record.id, @employee.leave_requests.order(:id).last.resumes_request_id
  end

  test "private family grounds are absent from manager cards notifications and team calendar" do
    record = create_childcare
    record.update_column(:employee_comment, "PRIVATE_BASIS_DETAIL")
    record.register_family!(by: @administrator, legal_review: family_review_attributes)
    sign_in_as(@manager)
    get manager_leave_requests_path
    assert_response :success
    assert_no_match(/PRIVATE_BASIS_DETAIL|Отпуск по уходу за ребёнком|Дата рождения ребёнка/, response.body)
    get manager_calendar_path(year: 2026, month: 10)
    assert_response :success
    assert_select ".team-timeline__bar[aria-label*='Длительное отсутствие']", count: 1
    assert_no_match(/Отпуск по уходу за ребёнком|PRIVATE_BASIS_DETAIL/, response.body)
    get manager_calendar_path(year: 2026, month: "all")
    assert_response :success
    assert_no_match(/Отпуск по уходу за ребёнком/, response.body)
    record.return_from_childcare!(by: @employee, return_on: Date.current)
    get notifications_path
    assert_response :success
    assert_no_match(/по уходу|PRIVATE_BASIS_DETAIL/, response.body)
  end

  test "invalid legal review types unknown fields and foreign return have no side effects" do
    record = create_childcare
    sign_in_as(@administrator)
    [ { document_reference: [] }, { reviewer_id: @administrator.id }, { conditions_confirmed: "yes" } ].each do |bad|
      assert_no_difference([ "LeaveLegalReview.count", "LeaveRequestEvent.count", "Notification.count" ]) do
        post register_admin_family_leave_path(record), params: { legal_review: family_review_attributes.merge(bad) }, as: :json
        assert_response :bad_request
      end
    end
    sign_in_as(@manager)
    post return_from_childcare_leave_request_path(record), params: { childcare_return: { return_on: "2026-10-14", confirmed: "1" } }
    assert_response :not_found
  end

  test "annual approval stores working year and ordinary rejection has no required review fields" do
    record = LeaveRequest.create!(employee: @employee, leave_type: @annual,
      starts_on: Date.new(2026, 12, 20), ends_on: Date.new(2027, 1, 20))
    sign_in_as(@manager)
    get manager_leave_requests_path
    assert_select "input[name='legal_review[working_year_starts_on]']"
    assert_select "button[formnovalidate][formaction='#{reject_manager_leave_request_path(record)}']"
    post_data = annual_review_attributes.transform_values { |value| value.is_a?(Date) ? value.iso8601 : value }
    patch approve_manager_leave_request_path(record), params: { legal_review: post_data }
    assert_response :redirect
    assert_predicate record.reload, :approved?
  end

  private

  def childcare_attributes
    { leave_type_id: @childcare.id, starts_on: "2026-10-01", ends_on: "2028-01-01",
      full_day: "1", child_born_on: "2025-01-01", care_relationship: "father" }
  end
end
