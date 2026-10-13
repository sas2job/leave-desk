require "test_helper"

module Manager
  class LeaveRequestsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @manager = create_user("manager@example.test", role: :manager)
      @other_manager = create_user("other-manager@example.test", role: :manager)
      @employee = create_user("employee@example.test", manager: @manager)
      @other_employee = create_user("other@example.test", manager: @other_manager)
      @leave_type = LeaveType.create!(name: "Annual leave", code: "TEST_ANNUAL")
    end

    test "manager lists only direct report requests" do
      managed_request = create_request(@employee, starts_on: Date.new(2026, 11, 1))
      other_request = create_request(@other_employee, starts_on: Date.new(2026, 12, 1))
      sign_in_as(@manager)

      get manager_leave_requests_path

      assert_response :success
      assert_select "body", text: /01\.11\.2026/
      assert_select "summary", text: "История заявки"
      assert_select "##{dom_id(managed_request)}"
      assert_select "##{dom_id(other_request)}", count: 0
      assert_no_match(/01\.12\.2026/, response.body)
    end

    test "manager approves direct report request" do
      leave_request = create_request(@employee)
      sign_in_as(@manager)

      patch approve_manager_leave_request_path(leave_request),
        params: { review_comment: "Approved" }

      assert_redirected_to manager_leave_requests_path
      assert_predicate leave_request.reload, :approved?
      assert_equal @manager, leave_request.reviewer
      assert_equal "approved", @employee.notifications.last.leave_request_event.event_type
    end

    test "shows a repeated review error in Russian" do
      leave_request = create_request(@employee)
      sign_in_as(@manager)
      patch approve_manager_leave_request_path(leave_request)

      patch approve_manager_leave_request_path(leave_request)

      assert_redirected_to manager_leave_requests_path
      follow_redirect!
      assert_select ".flash--alert", text: "Рассмотреть можно только заявку на рассмотрении"
    end

    test "manager queue renders an action-specific CSRF token for rejection" do
      leave_request = create_request(@employee)
      sign_in_as(@manager)

      previous_forgery_protection = ActionController::Base.allow_forgery_protection
      begin
        ActionController::Base.allow_forgery_protection = true
        get manager_leave_requests_path
      ensure
        ActionController::Base.allow_forgery_protection = previous_forgery_protection
      end

      approve_form = css_select(
        "form[action='#{approve_manager_leave_request_path(leave_request)}']"
      ).sole
      approve_token = approve_form.at_css("input[name='authenticity_token']")["value"]
      reject_button = approve_form.at_css(
        "button[formaction='#{reject_manager_leave_request_path(leave_request)}']"
      )

      assert_equal "authenticity_token", reject_button["name"]
      refute_equal approve_token, reject_button["value"]
    end

    test "manager queue has unique review fields and a danger rejection action" do
      first_request = create_request(@employee)
      second_request = create_request(@other_employee)
      @other_employee.update!(manager: @manager)
      sign_in_as(@manager)

      get manager_leave_requests_path

      assert_response :success
      assert_select "textarea#review_comment_#{first_request.id}", count: 1
      assert_select "textarea#review_comment_#{second_request.id}", count: 1
      assert_select "label[for='review_comment_#{first_request.id}']", count: 1
      assert_select "label[for='review_comment_#{second_request.id}']", count: 1
      assert_select "button.button--danger[formaction='#{reject_manager_leave_request_path(first_request)}']", count: 1
    end

    test "manager submits the rendered rejection form with CSRF protection" do
      leave_request = create_request(@employee)
      sign_in_as(@manager)

      previous_forgery_protection = ActionController::Base.allow_forgery_protection
      begin
        ActionController::Base.allow_forgery_protection = true
        get manager_leave_requests_path

        form = css_select(
          "form[action='#{approve_manager_leave_request_path(leave_request)}']"
        ).sole
        reject_button = form.at_css(
          "button[formaction='#{reject_manager_leave_request_path(leave_request)}']"
        )
        submitted_fields = form.css("input[type='hidden'][name]").map do |input|
          [ input["name"], input["value"] ]
        end
        submitted_fields << [ "review_comment", "Rejected" ]
        submitted_fields << [ reject_button["name"], reject_button["value"] ]

        post reject_manager_leave_request_path(leave_request),
          params: URI.encode_www_form(submitted_fields),
          headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }

        assert_redirected_to manager_leave_requests_path
        assert_predicate leave_request.reload, :rejected?
        assert_equal @manager, leave_request.reviewer
      ensure
        ActionController::Base.allow_forgery_protection = previous_forgery_protection
      end
    end

    test "manager rejects direct report request" do
      leave_request = create_request(@employee)
      sign_in_as(@manager)

      patch reject_manager_leave_request_path(leave_request),
        params: { review_comment: "Rejected" }

      assert_redirected_to manager_leave_requests_path
      assert_predicate leave_request.reload, :rejected?
      assert_equal @manager, leave_request.reviewer
      assert_equal "rejected", @employee.notifications.last.leave_request_event.event_type
    end

    test "manager cannot submit a structured review comment" do
      leave_request = create_request(@employee)
      sign_in_as(@manager)

      patch reject_manager_leave_request_path(leave_request),
        params: { review_comment: { nested: "not a comment" } }

      assert_response :bad_request
      assert_predicate leave_request.reload, :pending?
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
