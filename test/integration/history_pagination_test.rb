require "test_helper"

class HistoryPaginationTest < ActionDispatch::IntegrationTest
  setup do
    @manager = User.create!(name: "Manager", email_address: "manager@example.test",
      password: "test-password", role: :manager)
    @employee = User.create!(name: "Employee", email_address: "employee@example.test",
      password: "test-password", manager: @manager)
    @other_manager = User.create!(name: "Other Manager", email_address: "other-manager@example.test",
      password: "test-password", role: :manager)
    @outsider = User.create!(name: "Outsider", email_address: "outsider@example.test",
      password: "test-password", manager: @other_manager)
    @leave_type = LeaveType.create!(name: "Annual", code: "TEST_ANNUAL")
    @requests = (1..27).map { |day| create_request(@employee, day) }
    @foreign_request = create_request(@outsider, 28)
  end

  test "personal history keeps older pages stable and scoped" do
    sign_in_as(@employee)

    get leave_requests_path
    assert_response :success
    assert_equal @requests.last(25).reverse.map(&:id), visible_request_ids
    assert_select "a[href='#{leave_requests_path(before: @requests[2].id)}']",
      text: "Более ранние записи"

    new_request = create_request(@employee, 29)
    get leave_requests_path(before: @requests[2].id)
    assert_response :success
    assert_equal @requests.first(2).reverse.map(&:id), visible_request_ids
    assert_select "a[href='#{leave_requests_path}']", text: "К новым записям"
    assert_select "##{dom_id(@foreign_request)}", count: 0
    assert_select "##{dom_id(new_request)}", count: 0
  end

  test "manager history remains scoped and notification links reach older requests" do
    sign_in_as(@manager)

    get manager_leave_requests_path
    assert_response :success
    assert_equal @requests.last(25).reverse.map(&:id), visible_request_ids
    assert_select "##{dom_id(@foreign_request)}", count: 0

    get manager_leave_requests_path(before: @requests[2].id)
    assert_response :success
    assert_equal @requests.first(2).reverse.map(&:id), visible_request_ids

    get notifications_path(before: @manager.notifications.order(:id).third.id + 1)
    assert_response :success
    target = @requests.first
    assert_select "a[href='#{manager_leave_requests_path(before: target.id + 1, anchor: dom_id(target))}']"
    get manager_leave_requests_path(before: target.id + 1)
    assert_select "##{dom_id(target)}"
  end

  test "notifications paginate without omissions and mark all includes older pages" do
    notifications = @manager.notifications.order(:id).to_a
    notifications.last(25).each { |notification| notification.update!(read_at: Time.current) }
    sign_in_as(@manager)

    get notifications_path
    assert_response :success
    assert_equal notifications.last(25).reverse.map(&:id), visible_notification_ids
    assert_select "form[action='#{mark_all_read_notifications_path}']"
    assert_select "##{dom_id(@other_manager.notifications.first)}", count: 0

    create_request(@employee, 29)
    get notifications_path(before: notifications[2].id)
    assert_response :success
    assert_equal notifications.first(2).reverse.map(&:id), visible_notification_ids
    assert_select "##{dom_id(@other_manager.notifications.first)}", count: 0

    patch mark_all_read_notifications_path
    assert_redirected_to notifications_path
    assert_equal 0, @manager.notifications.unread.count
  end

  test "rejects malformed cursors on every history page" do
    sign_in_as(@manager)
    [ manager_leave_requests_path, notifications_path ].each do |path|
      [ "0", "-1", "1x", "9223372036854775808" ].each do |cursor|
        get path, params: { before: cursor }
        assert_response :bad_request
      end
    end

    sign_in_as(@employee)
    get leave_requests_path, params: { before: [ "1" ] }
    assert_response :bad_request
  end

  test "employee notification links to an older personal request" do
    target = @requests.first
    target.reject!(by: @manager)
    sign_in_as(@employee)

    get notifications_path
    assert_response :success
    assert_select "a[href='#{leave_requests_path(before: target.id + 1, anchor: dom_id(target))}']"
    get leave_requests_path(before: target.id + 1)
    assert_select "##{dom_id(target)}"
  end

  private

  def create_request(employee, day)
    date = Date.new(2026, 11, 1) + (day - 1).days
    LeaveRequest.create!(employee:, leave_type: @leave_type, starts_on: date, ends_on: date)
  end

  def visible_request_ids
    css_select("article[id^='leave_request_']").map { |card| card["id"].delete_prefix("leave_request_").to_i }
  end

  def visible_notification_ids
    css_select("article[id^='notification_']").map { |card| card["id"].delete_prefix("notification_").to_i }
  end
end
