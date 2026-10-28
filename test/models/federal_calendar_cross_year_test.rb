require "test_helper"

class FederalCalendarCrossYearTest < ActiveSupport::TestCase
  setup do
    @administrator = User.create!(name: "Administrator", email_address: "cross-year-admin@example.test",
      password: "test-password", role: :administrator)
    @employee = User.create!(name: "Employee", email_address: "cross-year-employee@example.test",
      password: "test-password")
    @leave_type = LeaveType.create!(name: "Annual leave", code: "CROSS_YEAR_ANNUAL",
      holiday_handling: :exclude_public_holidays)
  end

  test "changes in every intersected year flag a historical request" do
    calendar_2026 = create_calendar(2026)
    calendar_2027 = create_calendar(2027)
    request = create_historical_request(calendar_unverified: false)

    calendar_2026.update!(public_holidays: calendar_2026.public_holidays + [ Date.new(2026, 12, 31) ])

    assert_predicate request.reload, :calendar_unverified?
    assert_equal 4, request.duration_in_days
    assert_equal 3, request.calendar_duration_in_days

    request.reconcile_calendar!(by: @administrator)
    assert_not request.reload.calendar_unverified?
    assert_equal 3, request.duration_in_days

    calendar_2027.update!(public_holidays: calendar_2027.public_holidays - [ Date.new(2027, 1, 8) ])

    assert_predicate request.reload, :calendar_unverified?
    assert_equal 3, request.duration_in_days
    assert_equal 4, request.calendar_duration_in_days
    assert_equal 2, request.events.calendar_unverified.count
    assert_equal 2, @administrator.notifications.count
  end

  test "reconciliation requires every intersected calendar" do
    create_calendar(2026)
    request = create_historical_request(calendar_unverified: true)

    error = assert_raises(LeaveRequest::InvalidTransition) do
      request.reconcile_calendar!(by: @administrator)
    end

    assert_equal "Календарь 2027 года ещё не внесён", error.message
    assert_predicate request.reload, :calendar_unverified?
    assert_equal 4, request.duration_in_days
    assert_empty request.events.calendar_reconciled
  end

  private

  def create_calendar(year)
    FederalCalendar.create!(year:, legal_basis: "Federal calendar #{year}",
      public_holidays: RussianFederalHoliday.fixed_dates_for(year))
  end

  def create_historical_request(calendar_unverified:)
    request = LeaveRequest.create!(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 12, 30), ends_on: Date.new(2026, 12, 31))
    request.update_columns(ends_on: Date.new(2027, 1, 10), duration_half_days: 8,
      calendar_unverified:)
    request
  end
end
