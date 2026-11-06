require "test_helper"

module Manager
  class CalendarsControllerTest < ActionDispatch::IntegrationTest
    include DateIterationBudgetHelper

    setup do
      travel_to Date.new(2026, 10, 1)
      @manager = create_user("manager@example.test", role: :manager)
      @employee = create_user("employee@example.test", manager: @manager,
        birthday_on: Date.new(1990, 5, 12))
      @leave_type = LeaveType.create!(name: "Annual", code: "TEST_ANNUAL")
    end

    test "manager sees direct report annual calendar" do
      request = travel_to Date.new(2026, 5, 1) do
        LeaveRequest.create!(employee: @employee, leave_type: @leave_type,
          starts_on: Date.new(2026, 6, 10), ends_on: Date.new(2026, 6, 12))
      end
      request.approve!(by: @manager)
      sign_in_as(@manager)

  get manager_calendar_path(year: 2026, month: "all")

      assert_response :success
      assert_select "body", text: /Example User/
      assert_select "td.leave", minimum: 3
      assert_select "td.birthday", text: "ДР"
      assert_select "nav.calendar-month-jump a[href='#team-year-date-2026-10-01']"
      assert_select "th#team-year-date-2026-10-01"
    end

    test "overlap document includes only relevant months and direct reports and denies other roles" do
      second = create_user("overlap-second@example.test", manager: @manager)
      [ @employee, second ].each do |employee|
        request = LeaveRequest.create!(employee:, leave_type: @leave_type,
          starts_on: Date.new(2026, 10, 10), ends_on: Date.new(2026, 10, 12))
        request.approve!(by: @manager)
      end
      sign_in_as(@manager)
      get manager_calendar_overlaps_path(year: 2026, month: "all", format: :md)
      assert_response :success
      assert_includes response.headers["Content-Disposition"], "attachment"
      assert_includes response.body, "Дней с пересечениями: 3"
      assert_includes response.body, "октябрь 2026"
      assert_not_includes response.body, "ноябрь 2026"
      sign_in_as(@employee)
      get manager_calendar_overlaps_path(year: 2026, month: "all", format: :md)
      assert_response :forbidden
      administrator = create_user("overlap-admin@example.test", role: :administrator)
      sign_in_as(administrator)
      get manager_calendar_overlaps_path(year: 2026, month: "all", format: :md)
      assert_response :forbidden
      get manager_calendar_path(year: 2026, month: 10)
      assert_select ".calendar-summary", text: /Дней с пересечениями/, count: 0
      assert_select ".team-timeline__coverage", count: 0
    end

    test "shows only visible dates for a long approved request" do
    request = LeaveRequest.create!(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 10, 1), ends_on: Date.new(2026, 10, 31))
    request.update_columns(starts_on: Date.new(2000, 1, 1), ends_on: Date.new(2100, 12, 31))
      request.approve!(by: @manager)
      sign_in_as(@manager)

      successor_calls = count_date_successors do
        get manager_calendar_path(year: 2026, month: 10)
      end

      assert_response :success
      assert_select ".team-timeline__bar[style*='span 31']", count: 1
      assert_operator successor_calls, :<=, 200
    end

    test "loads only approved requests overlapping the visible month" do
      no_leave = create_user("no-leave@example.test", manager: @manager, name: "No Leave")
      other_manager = create_user("other-manager@example.test", role: :manager)
      outsider = create_user("outsider@example.test", manager: other_manager, name: "Outside")

      [ [ @employee, Date.new(2025, 10, 15), @manager ],
        [ @employee, Date.new(2026, 10, 15), @manager ],
        [ @employee, Date.new(2027, 10, 15), @manager ],
        [ outsider, Date.new(2026, 10, 17), other_manager ] ].each do |employee, date, reviewer|
        temporary_date = date.year == 2026 ? date : Date.new(2026, date.year == 2025 ? 11 : 12, date.day)
      request = LeaveRequest.create!(employee:, leave_type: @leave_type,
        starts_on: temporary_date, ends_on: temporary_date)
      request.update_columns(starts_on: date, ends_on: date) unless date.year == 2026
        request.approve!(by: reviewer)
      end
      LeaveRequest.create!(employee: @employee, leave_type: @leave_type,
        starts_on: Date.new(2026, 10, 16), ends_on: Date.new(2026, 10, 16))

      loaded_requests = 0
      subscriber = lambda do |*arguments|
        payload = arguments.last
        loaded_requests += payload[:record_count] if payload[:class_name] == "LeaveRequest"
      end

      sign_in_as(@manager)
      ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") do
        get manager_calendar_path(year: 2026, month: 10)
      end

      assert_response :success
      assert_equal 1, loaded_requests
      assert_select ".team-timeline__bar", count: 1
      assert_select ".team-timeline__name", text: no_leave.name
      assert_select ".team-timeline__name", text: outsider.name, count: 0
    end

    test "shows approved leave and birthday on the same day" do
      request = travel_to Date.new(2026, 5, 1) do
        LeaveRequest.create!(employee: @employee, leave_type: @leave_type,
          starts_on: Date.new(2026, 5, 12), ends_on: Date.new(2026, 5, 12))
      end
      request.approve!(by: @manager)
      sign_in_as(@manager)

      get manager_calendar_path(year: 2026, month: 5)

      assert_response :success
      assert_select ".team-timeline__bar[aria-label*='Annual'][style*='grid-column: 12']", count: 1
      assert_select ".team-timeline__birthday[style*='grid-column: 12']", text: "ДР"
    end

    test "timeline shows overlapping employees and the daily coverage" do
      teammate = create_user("teammate@example.test", manager: @manager, name: "Teammate")
      other_type = LeaveType.create!(name: "Sick leave", code: "TEST_SICK")
      first = LeaveRequest.create!(employee: @employee, leave_type: @leave_type,
        starts_on: Date.new(2026, 10, 14), ends_on: Date.new(2026, 10, 16))
      second = LeaveRequest.create!(employee: teammate, leave_type: other_type,
        starts_on: Date.new(2026, 10, 15), ends_on: Date.new(2026, 10, 17))
      first.approve!(by: @manager)
      second.approve!(by: @manager)
      sign_in_as(@manager)

      get manager_calendar_path(year: 2026, month: 10)

      assert_response :success
      assert_select ".team-timeline__bar.timeline-color--0[style*='grid-column: 14 / span 3'][aria-label*='Annual']", count: 1
      assert_select ".team-timeline__bar.timeline-color--1[style*='grid-column: 15 / span 3'][aria-label*='Sick leave']", count: 1
      assert_select ".team-timeline__count.is-overlap", text: "2", count: 2
      assert_select "a.calendar-focus-link[href='#team-date-2026-10-15']", text: "К пересечению →"
      assert_select "time#team-date-2026-10-15"
      assert_select ".calendar-legend__item", text: /Annual/
      assert_select ".calendar-legend__item", text: /Sick leave/
    end

    test "timeline uses the time of a partial-day absence" do
      request = LeaveRequest.create!(employee: @employee, leave_type: @leave_type,
        starts_on: Date.new(2026, 10, 20), ends_on: Date.new(2026, 10, 20),
        start_time: "09:00", end_time: "12:00")
      request.approve!(by: @manager)
      sign_in_as(@manager)

      get manager_calendar_path(year: 2026, month: 10)

      assert_response :success
      assert_select ".team-timeline__bar[style*='margin-left: 15.0px'][style*='margin-right: 20.0px'][aria-label*='09:00–12:00']", count: 1
    end

    test "defaults to the current month" do
      sign_in_as(@manager)

      travel_to Date.new(2026, 10, 9) do
        get manager_calendar_path
      end

      assert_response :success
      assert_select "h1", text: "Календарь октябрь 2026"
      assert_select ".team-timeline-wrap"
      assert_select ".team-timeline__date", count: 31
      assert_select ".team-timeline__track", count: 1
    end

    test "parses zero-padded months as decimal and falls back for invalid input" do
      sign_in_as(@manager)

      (1..12).each do |month|
        get manager_calendar_path(year: 2026, month: format("%02d", month))
        assert_response :success
        assert_select "h1", text: "Календарь #{I18n.l(Date.new(2026, month, 1), format: "%B %Y")}"
      end

      travel_to Date.new(2026, 10, 9) do
        get manager_calendar_path(year: 2026, month: "13")
        assert_response :success
        assert_select "h1", text: "Календарь октябрь 2026"
      end
    end

    test "accepts supported boundary years and rejects years outside them" do
      sign_in_as(@manager)

    [ 2025, 2050 ].each do |year|
        get manager_calendar_path(year:, month: 10)
        assert_response :success
        assert_select "h1", text: /октябрь #{year}/
      end

    [ 1976, 2024, 2051, 2100 ].each do |year|
        get manager_calendar_path(year:, month: 10)
        assert_response :success
        assert_select "h1", text: /октябрь 2026/
      end
    end

    test "navigation stops at January 2025" do
      sign_in_as(@manager)

      get manager_calendar_path(year: 2025, month: 1)
      assert_response :success
      assert_select "a[href='#{manager_calendar_path(year: 2024, month: 12)}']", count: 0

      get manager_calendar_path(year: 2025, month: "all")
      assert_response :success
      assert_select "a[href='#{manager_calendar_path(year: 2024, month: "all")}']", count: 0
    end

    test "navigation stops at December 2050" do
      sign_in_as(@manager)

      get manager_calendar_path(year: 2050, month: 12)
      assert_response :success
      assert_select "a[href='#{manager_calendar_path(year: 2051, month: 1)}']", count: 0

      get manager_calendar_path(year: 2050, month: "all")
      assert_response :success
      assert_select "a[href='#{manager_calendar_path(year: 2051, month: "all")}']", count: 0
    end

    test "parses years only as decimal" do
      sign_in_as(@manager)

      travel_to Date.new(2026, 10, 9) do
        get manager_calendar_path(year: "02030", month: "10")
        assert_response :success
        assert_select "h1", text: "Календарь октябрь 2030"

        get manager_calendar_path(year: "0x7ee", month: "10")
        assert_response :success
        assert_select "h1", text: "Календарь октябрь 2026"
      end
    end

    test "rejects decorated calendar numbers" do
      sign_in_as(@manager)

      travel_to Date.new(2026, 2, 9) do
        get manager_calendar_path(year: "2_030", month: "1_0")
        assert_response :success
        assert_select "h1", text: "Календарь февраль 2026"
      end
    end

    test "rejects structured calendar filters" do
      sign_in_as(@manager)

      get manager_calendar_path, params: { year: [ "2026" ] }
      assert_response :bad_request

      get manager_calendar_path, params: { month: { value: "10" } }
      assert_response :bad_request
    end

    test "employee cannot open manager calendar" do
      sign_in_as(@employee)
      get manager_calendar_path
      assert_response :forbidden
    end

    test "administrator sees all active employees in calendar" do
      administrator = create_user("admin@example.test", role: :administrator)
      create_user("other@example.test", name: "Other Employee", birthday_on: Date.new(1992, 10, 4))
      sign_in_as(administrator)

      get manager_calendar_path(year: 2026, month: 10)

      assert_response :success
      assert_select ".team-timeline__name", text: "Example User"
      assert_select ".team-timeline__name", text: "Other Employee"
      assert_select "details.site-nav__dropdown summary", text: "Календари"
      assert_select "a[href='#{manager_calendar_path}']", text: "Общий календарь"
      assert_select "a[href='#{calendar_path}']", text: "Мой календарь"
      assert_select ".team-timeline__birthday", text: "ДР", count: 1
    end

    private

    def create_user(email_address, role: :employee, manager: nil, birthday_on: nil, name: "Example User")
      User.create!(name:, email_address:, password: "test-password",
        role:, manager:, birthday_on:)
    end
  end
end
