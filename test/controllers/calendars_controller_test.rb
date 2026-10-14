require "test_helper"

class CalendarsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @manager = create_user("manager@example.test", role: :manager)
    @employee = create_user("employee@example.test", manager: @manager,
      birthday_on: Date.new(1990, 10, 9))
    @other_employee = create_user("other@example.test", manager: @manager)
    @leave_type = LeaveType.create!(name: "Ежегодный отпуск", code: "TEST_ANNUAL")
  end

  test "shows only the current user's pending and approved requests" do
    approved_request = create_request(@employee, starts_on: Date.new(2026, 10, 10))
    approved_request.approve!(by: @manager)
    create_request(@employee, starts_on: Date.new(2026, 10, 15))
    other_request = create_request(@other_employee, starts_on: Date.new(2026, 10, 20))
    other_request.approve!(by: @manager)
    sign_in_as(@employee)

    travel_to Date.new(2026, 10, 9) do
      get calendar_path
    end

    assert_response :success
    assert_select "h1", text: "Мой календарь — октябрь 2026"
    assert_select ".team-calendar td.leave", count: 2
    assert_select ".team-calendar td.leave-pending", count: 2
    assert_select ".team-calendar td.birthday", text: "ДР"
    assert_select "tbody th", count: 1
    assert_select "a[href='#{calendar_path}']", text: "Мой календарь"
    assert_select "summary", text: "Календари", count: 0
    assert_no_match(/other@example\.test/, response.body)
    assert_select ".team-calendar td.leave[title*='20.10.2026']", count: 0
  end

  test "shows transferred day off and working source weekend" do
    FederalCalendar.create!(year: 2026, legal_basis: "Постановление о переносах",
      public_holidays: RussianFederalHoliday.fixed_dates_for(2026),
      transfers: [ { "from" => "2026-10-10", "to" => "2026-10-12" } ])
    sign_in_as(@employee)

    get calendar_path(year: 2026, month: 10)

    assert_response :success
    assert_select "thead tr:last-child th:nth-child(10):not(.weekend)"
    assert_select "thead tr:last-child th:nth-child(12).weekend"
  end

  test "shows only visible dates for a request spanning the supported range" do
    request = LeaveRequest.create!(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 10, 1), ends_on: Date.new(2026, 10, 31))
    request.update_columns(starts_on: Date.new(2000, 1, 1), ends_on: Date.new(2100, 12, 31))
    request.approve!(by: @manager)
    sign_in_as(@employee)

    get calendar_path(year: 2026, month: 10)

    assert_response :success
    assert_select ".team-calendar td.leave", count: 31
  end

  test "shows approved morning and pending afternoon on the same date" do
    morning = LeaveRequest.create!(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 10, 20), ends_on: Date.new(2026, 10, 20),
      end_part: :morning)
    morning.approve!(by: @manager)
    LeaveRequest.create!(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 10, 20), ends_on: Date.new(2026, 10, 20),
      start_part: :afternoon)
    sign_in_as(@employee)

    get calendar_path(year: 2026, month: 10)

    assert_response :success
    assert_select ".team-calendar td.leave-split[title*='20.10.2026']" do
      assert_select ".calendar-half--morning.calendar-half--approved", text: "С"
      assert_select ".calendar-half--afternoon.calendar-half--pending", text: "Р"
    end
  end

  test "shows adjacent requests that share a boundary date" do
    first = LeaveRequest.create!(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 10, 19), ends_on: Date.new(2026, 10, 20),
      end_part: :morning)
    first.approve!(by: @manager)
    LeaveRequest.create!(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 10, 20), ends_on: Date.new(2026, 10, 21),
      start_part: :afternoon)
    sign_in_as(@employee)

    get calendar_path(year: 2026, month: 10)

    assert_response :success
    assert_select ".team-calendar td.leave-split[title*='20.10.2026']" do
      assert_select ".calendar-half--morning.calendar-half--approved"
      assert_select ".calendar-half--afternoon.calendar-half--pending"
    end
  end

  test "parses zero-padded months as decimal and falls back for invalid input" do
    sign_in_as(@employee)

    (1..12).each do |month|
      get calendar_path(year: 2026, month: format("%02d", month))
      assert_response :success
      assert_select "h1", text: "Мой календарь — #{I18n.l(Date.new(2026, month, 1), format: "%B %Y")}"
    end

    travel_to Date.new(2026, 10, 9) do
      %w[00 13 abc].each do |month|
        get calendar_path(year: 2026, month:)
        assert_response :success
        assert_select "h1", text: "Мой календарь — октябрь 2026"
      end
    end
  end

  test "parses years only as decimal" do
    sign_in_as(@employee)

    travel_to Date.new(2026, 10, 9) do
      get calendar_path(year: "02030", month: "10")
      assert_response :success
      assert_select "h1", text: "Мой календарь — октябрь 2030"

      get calendar_path(year: "0x7ee", month: "10")
      assert_response :success
      assert_select "h1", text: "Мой календарь — октябрь 2026"
    end
  end

  test "rejects decorated calendar numbers" do
    sign_in_as(@employee)

    travel_to Date.new(2026, 2, 9) do
      get calendar_path(year: "2_030", month: "1_0")
      assert_response :success
      assert_select "h1", text: "Мой календарь — февраль 2026"
    end
  end

  test "rejects structured calendar filters" do
    sign_in_as(@employee)

    get calendar_path, params: { year: [ "2026" ] }
    assert_response :bad_request

    get calendar_path, params: { month: { value: "10" } }
    assert_response :bad_request
  end

  private

  def create_user(email_address, role: :employee, manager: nil, birthday_on: nil)
    User.create!(name: "Example User", email_address:, password: "test-password",
      role:, manager:, birthday_on:)
  end

  def create_request(employee, starts_on:)
    LeaveRequest.create!(employee:, leave_type: @leave_type, starts_on:,
      ends_on: starts_on + 1.day)
  end
end
