require "test_helper"

class LeaveRecallsControllerTest < ActionDispatch::IntegrationTest
  include LeaveRecallTestHelper

  setup { prepare_recall_scenario }

  test "manager proposes employee consents and manager records order through separate forms" do
    sign_in_as(@manager)
    get manager_leave_requests_path
    assert_select "a[href='#{new_leave_request_recall_path(@leave_request)}']", text: "Предложить отзыв"
    post leave_request_recalls_path(@leave_request), params: { recall: proposal_attributes }
    assert_equal "[FILTERED]", request.filtered_parameters["recall"]
    recall = @leave_request.leave_recalls.sole
    assert_redirected_to leave_request_recall_path(@leave_request, recall)

    sign_in_as(@employee)
    get leave_request_recall_path(@leave_request, recall)
    assert_select "form[action='#{consent_leave_request_recall_path(@leave_request, recall)}']", count: 1
    assert_select "form[action='#{decline_leave_request_recall_path(@leave_request, recall)}']", count: 1
    post consent_leave_request_recall_path(@leave_request, recall), params: { recall: {
      consent_confirmed: "1", remainder_option: "next_work_year"
    } }
    assert_response :see_other
    assert_predicate @leave_request.reload, :approved?

    sign_in_as(@manager)
    get leave_request_recall_path(@leave_request, recall)
    assert_select "input[name='recall[consent_reference]']"
    post confirm_leave_request_recall_path(@leave_request, recall), params: { recall: confirmation_attributes }
    assert_response :see_other
    assert_predicate @leave_request.reload, :recalled?
    follow_redirect!
    assert_select "p", text: /Неиспользованная часть:.*5 дн\./
    get manager_leave_requests_path
    assert_response :success
    assert_select "a[href='#{leave_request_recall_path(@leave_request, recall)}']", text: /Отзыв оформлен/
    get notifications_path
    assert_response :success
    assert_select "a", text: /Заявка №#{@leave_request.id}: сотрудник согласился на отзыв/
  end

  test "employee may decline without explaining and no leave data changes" do
    recall = propose_recall
    sign_in_as(@employee)
    post decline_leave_request_recall_path(@leave_request, recall)
    assert_response :see_other
    assert_predicate recall.reload, :declined?
    assert_predicate @leave_request.reload, :approved?
    assert_nil @leave_request.recalled_on
  end

  test "other employees and former manager cannot access or change recall" do
    recall = propose_recall
    outsider = User.create!(name: "Outsider", email_address: "recall-outsider@example.test", password: "test-password")
    sign_in_as(outsider)
    assert_no_difference([ "LeaveRequestEvent.count", "Notification.count", "LeaveRecall.count" ]) do
      get leave_request_recall_path(@leave_request, recall)
      assert_response :not_found
      post decline_leave_request_recall_path(@leave_request, recall)
      assert_response :not_found
      post leave_request_recalls_path(@leave_request), params: { recall: proposal_attributes }
      assert_response :forbidden
    end
    consent_to_recall(recall)
    @employee.update!(manager: nil)
    sign_in_as(@manager)
    assert_no_difference([ "LeaveRequestEvent.count", "Notification.count" ]) do
      post confirm_leave_request_recall_path(@leave_request, recall), params: { recall: confirmation_attributes }
      assert_response :not_found
    end
    assert_predicate @leave_request.reload, :approved?
  end

  test "manager cannot consent on behalf of employee and explicit consent checkbox is required" do
    recall = propose_recall
    sign_in_as(@manager)
    post consent_leave_request_recall_path(@leave_request, recall), params: { recall: {
      consent_confirmed: "1", remainder_option: "next_work_year"
    } }
    assert_response :not_found
    sign_in_as(@employee)
    assert_no_difference([ "LeaveRequestEvent.count", "Notification.count" ]) do
      post consent_leave_request_recall_path(@leave_request, recall), params: { recall: {
        remainder_option: "next_work_year"
      } }, as: :json
      assert_response :unprocessable_entity
    end
    assert_predicate recall.reload, :proposed?
  end

  test "malformed and unknown proposal inputs have no side effects" do
    sign_in_as(@manager)
    [ { reason: [ "invalid" ] }, { reason: 12 }, { status: "confirmed" }, { employee_id: @employee.id } ].each do |invalid|
      assert_no_difference([ "LeaveRecall.count", "LeaveRequestEvent.count", "Notification.count" ]) do
        post leave_request_recalls_path(@leave_request), params: { recall: proposal_attributes.merge(invalid) }, as: :json
        assert_response :bad_request
      end
    end
    [ "infinity", "2026-99-99", "2026-10-13" ].each do |date|
      assert_no_difference([ "LeaveRecall.count", "LeaveRequestEvent.count", "Notification.count" ]) do
        post leave_request_recalls_path(@leave_request), params: { recall: proposal_attributes.merge(return_on: date) }, as: :json
        assert_response :unprocessable_entity
        assert_equal "[FILTERED]", request.filtered_parameters["recall"]
      end
    end
  end

  test "rendered consent form works with CSRF protection and refusal has its own form" do
    recall = propose_recall
    sign_in_as(@employee)
    previous = ActionController::Base.allow_forgery_protection
    begin
      ActionController::Base.allow_forgery_protection = true
      get leave_request_recall_path(@leave_request, recall)
      form = css_select("form[action='#{consent_leave_request_recall_path(@leave_request, recall)}']").sole
      token = form.at_css("input[name='authenticity_token']")["value"]
      post consent_leave_request_recall_path(@leave_request, recall), params: {
        authenticity_token: token, recall: { consent_confirmed: "1", remainder_option: "next_work_year" }
      }
      assert_response :see_other
      assert_predicate recall.reload, :consented?
    ensure
      ActionController::Base.allow_forgery_protection = previous
    end
  end

  test "calendars show used part and exclude recalled tail including year overview" do
    recall = propose_recall
    consent_to_recall(recall)
    confirm_recall(recall)
    sign_in_as(@employee)
    get calendar_path(year: 2026, month: 10)
    assert_response :success
    assert_select ".personal-month__day[data-date='2026-10-15'] .calendar-event", count: 1
    assert_select ".personal-month__day[data-date='2026-10-16'] .calendar-event", count: 0
    assert_select ".calendar-agenda__period", text: /15\.10\.2026/
    get calendar_path(year: 2026, month: "all")
    assert_response :success
    assert_select ".personal-year__day.has-approved[data-date='2026-10-15']", count: 1
    assert_select ".personal-year__day.has-approved[data-date='2026-10-16']", count: 0
    sign_in_as(@manager)
    get manager_calendar_path(year: 2026, month: 10)
    assert_response :success
    assert_select ".team-timeline__bar[style*='span 15']", count: 1
    assert_select ".team-timeline__bar[aria-label*='15.10.2026']", count: 1
    get manager_calendar_path(year: 2026, month: "all")
    assert_response :success
  end

  private

  def proposal_attributes
    { return_on: "2026-10-16", reason: "Срочная задача команды", eligibility_confirmed: "1" }
  end

  def confirmation_attributes
    { order_number: "TEST-12", order_on: "2026-10-14", consent_reference: "Согласие от 14.10.2026",
      eligibility_confirmed: "1" }
  end
end
