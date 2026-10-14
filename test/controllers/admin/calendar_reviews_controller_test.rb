require "test_helper"

module Admin
  class CalendarReviewsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @administrator = User.create!(name: "Administrator", email_address: "admin@example.test",
        password: "test-password", role: :administrator)
      @employee = User.create!(name: "Employee", email_address: "employee@example.test",
        password: "test-password")
      leave_type = LeaveType.create!(name: "Annual", code: "TEST_ANNUAL",
        holiday_handling: :exclude_public_holidays)
      @leave_request = LeaveRequest.create!(employee: @employee, leave_type:,
        starts_on: Date.new(2026, 6, 11), ends_on: Date.new(2026, 6, 13))
    end

    test "administrator sees flagged request and receives notification" do
      sign_in_as(@administrator)
      get notifications_path
      assert_response :success
      assert_select "body", text: /Заявка №#{@leave_request.id} требует проверки календаря/
      assert_select "a[href='#{admin_calendar_reviews_path(anchor: dom_id(@leave_request))}']"

      get admin_calendar_reviews_path
      assert_response :success
      assert_select "##{dom_id(@leave_request)}", text: /Календарь 2026 года ещё не внесён/
    end

    test "administrator explicitly reconciles request after calendar import" do
      FederalCalendar.create!(year: 2026, legal_basis: "НПА",
        public_holidays: [ Date.new(2026, 1, 1) ])
      sign_in_as(@administrator)
      get admin_calendar_reviews_path
      assert_select "##{dom_id(@leave_request)}", text: /По внесённому календарю: 3 дн./

      patch admin_calendar_review_path(@leave_request)
      assert_redirected_to admin_calendar_reviews_path
      assert_equal 3, @leave_request.reload.duration_in_days
      assert_not @leave_request.calendar_unverified?
      assert_predicate @leave_request.events.last, :calendar_reconciled?
    end

    test "employee cannot review calendar" do
      sign_in_as(@employee)
      get admin_calendar_reviews_path
      assert_response :forbidden
      patch admin_calendar_review_path(@leave_request)
      assert_response :forbidden
      assert_predicate @leave_request.reload, :calendar_unverified?
    end

    test "zero duration after import stays flagged for separate resolution" do
      FederalCalendar.create!(year: 2026, legal_basis: "Изменённый перечень",
        public_holidays: [ Date.new(2026, 6, 11), Date.new(2026, 6, 12), Date.new(2026, 6, 13) ])
      sign_in_as(@administrator)

      get admin_calendar_reviews_path
      assert_select "##{dom_id(@leave_request)}", text: /Новый расчёт не даёт положительной длительности/
      assert_select "##{dom_id(@leave_request)} form", count: 0

      patch admin_calendar_review_path(@leave_request)
      assert_redirected_to admin_calendar_reviews_path
      assert_predicate @leave_request.reload, :calendar_unverified?
      assert_equal 2, @leave_request.duration_in_days
    end
  end
end
