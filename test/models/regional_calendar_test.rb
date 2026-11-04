require "test_helper"

class RegionalCalendarTest < ActiveSupport::TestCase
  setup do
    travel_to Date.new(2026, 1, 1)
    @tatarstan = Region.create!(code: "RU-TA", name: "Республика Татарстан")
    @bashkortostan = Region.create!(code: "RU-BA", name: "Республика Башкортостан")
    @employee = User.create!(name: "Employee", email_address: "regional-employee@example.test",
      password: "test-password", region: @tatarstan)
    @administrator = User.create!(name: "Administrator", email_address: "regional-admin@example.test",
      password: "test-password", role: :administrator)
    @annual = LeaveType.create!(name: "Annual", code: "REGIONAL_ANNUAL",
      holiday_handling: :exclude_public_holidays)
    @unpaid = LeaveType.create!(name: "Unpaid", code: "REGIONAL_UNPAID",
      holiday_handling: :include_public_holidays)
    FederalCalendar.create!(year: 2026, legal_basis: "Статья 112 ТК РФ",
      public_holidays: RussianFederalHoliday.fixed_dates_for(2026))
  end

  test "regional public holiday is excluded from annual leave and extra day off is included" do
    calendar = RegionalCalendar.create!(region: @tatarstan, year: 2026,
      legal_basis: "Закон Республики Татарстан", complete: true,
      public_holidays: [ Date.new(2026, 11, 6) ],
      additional_days_off: [ Date.new(2026, 11, 9) ])
    annual = create_request(@annual, Date.new(2026, 11, 5), Date.new(2026, 11, 9))

    assert_equal @tatarstan, annual.region
    assert_equal 4, annual.duration_in_days
    assert_not annual.calendar_unverified?
    assert calendar.day_off?(Date.new(2026, 11, 9))
    assert_includes FederalCalendar.nonworking_dates([ Date.new(2026, 11, 9) ],
      region_id: @tatarstan.id), Date.new(2026, 11, 9)
    assert_not_includes FederalCalendar.nonworking_dates([ Date.new(2026, 11, 9) ],
      region_id: @bashkortostan.id), Date.new(2026, 11, 9)

    annual.cancel!
    unpaid = create_request(@unpaid, Date.new(2026, 11, 5), Date.new(2026, 11, 9))
    assert_equal 5, unpaid.duration_in_days
  end

  test "federal and regional holidays on the same date count once" do
    RegionalCalendar.create!(region: @tatarstan, year: 2026,
      legal_basis: "Закон Республики Татарстан", complete: true,
      public_holidays: [ Date.new(2026, 11, 4) ])

    request = create_request(@annual, Date.new(2026, 11, 3), Date.new(2026, 11, 5))

    assert_equal 2, request.duration_in_days
  end

  test "regional holiday affects only employees assigned to that region" do
    RegionalCalendar.create!(region: @tatarstan, year: 2026,
      legal_basis: "Закон Республики Татарстан", complete: true,
      public_holidays: [ Date.new(2026, 11, 6) ])
    RegionalCalendar.create!(region: @bashkortostan, year: 2026,
      legal_basis: "Закон Республики Башкортостан", complete: true, public_holidays: [])
    other_employee = User.create!(name: "Other Employee", email_address: "other-region@example.test",
      password: "test-password", region: @bashkortostan)

    tatarstan_request = create_request(@annual, Date.new(2026, 11, 5), Date.new(2026, 11, 7))
    other_request = LeaveRequest.create!(employee: other_employee, leave_type: @annual,
      starts_on: Date.new(2026, 11, 5), ends_on: Date.new(2026, 11, 7),
      start_time: "00:00", end_time: "24:00")

    assert_equal 2, tatarstan_request.duration_in_days
    assert_equal 3, other_request.duration_in_days
    assert_not tatarstan_request.calendar_unverified?
    assert_not other_request.calendar_unverified?
  end

  test "regional calendar missing at creation requires explicit reconciliation" do
    request = create_request(@annual, Date.new(2026, 11, 5), Date.new(2026, 11, 7))

    assert_predicate request, :calendar_unverified?
    assert_match(/Региональный календарь 2026/, assert_raises(LeaveRequest::InvalidTransition) {
      request.reconcile_calendar!(by: @administrator)
    }.message)

    RegionalCalendar.create!(region: @tatarstan, year: 2026,
      legal_basis: "Закон Республики Татарстан", complete: true,
      public_holidays: [ Date.new(2026, 11, 6) ])
    assert_equal 3, request.reload.duration_in_days
    assert_equal 2, request.calendar_duration_in_days

    request.reconcile_calendar!(by: @administrator)
    assert_equal 2, request.reload.duration_in_days
    assert_not request.calendar_unverified?
    assert_equal 1, request.events.calendar_reconciled.count
  end

  test "changing regional holidays flags only affected active requests and preserves the region snapshot" do
    calendar = RegionalCalendar.create!(region: @tatarstan, year: 2026,
      legal_basis: "Закон Республики Татарстан", complete: true, public_holidays: [])
    request = create_request(@annual, Date.new(2026, 11, 5), Date.new(2026, 11, 7))
    @employee.update!(region: @bashkortostan)

    calendar.update!(additional_days_off: [ Date.new(2026, 11, 9) ])
    assert_not request.reload.calendar_unverified?

    calendar.update!(public_holidays: [ Date.new(2026, 11, 6) ])
    assert_equal @tatarstan.id, request.reload.region_id
    assert_predicate request, :calendar_unverified?
    assert_equal 3, request.duration_in_days
    assert_equal 2, request.calendar_duration_in_days
    assert_equal 1, request.events.calendar_unverified.count
  end

  test "rejects malformed and out of year dates before saving" do
    calendar = RegionalCalendar.new(region: @tatarstan, year: 2026,
      legal_basis: "Закон Республики Татарстан")
    calendar.public_holidays_input = "2026-11-06\n2027-11-06"
    calendar.additional_days_off_input = "2026-02-30"

    assert_not calendar.valid?
    assert_predicate calendar.errors[:public_holidays], :present?
    assert_predicate calendar.errors[:additional_days_off_input], :present?
  end

  test "bounds a single oversized date input before parsing it" do
    calendar = RegionalCalendar.new(region: @tatarstan, year: 2026,
      legal_basis: "Закон Республики Татарстан")
    calendar.public_holidays_input = "A" * 10_000

    assert_not calendar.valid?
    assert_includes calendar.errors[:public_holidays_input], "не могут превышать 8 КиБ"
    assert_empty calendar.public_holidays
  end

  test "rejects non-string date input without raising an exception" do
    [ 1, nil ].each do |input|
      calendar = RegionalCalendar.new(region: @tatarstan, year: 2026,
        legal_basis: "Закон Республики Татарстан", public_holidays_input: input)

      assert_not calendar.valid?
      assert_predicate calendar.errors[:public_holidays_input], :present?
      assert_empty calendar.public_holidays
    end
  end

  private

  def create_request(leave_type, starts_on, ends_on)
    LeaveRequest.create!(employee: @employee, leave_type:, starts_on:, ends_on:,
      start_time: "00:00", end_time: "24:00")
  end
end
