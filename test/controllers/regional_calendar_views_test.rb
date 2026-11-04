require "test_helper"

class RegionalCalendarViewsTest < ActionDispatch::IntegrationTest
  setup do
    @manager = User.create!(name: "Manager", email_address: "regional-manager@example.test",
      password: "test-password", role: :manager)
    region = Region.create!(code: "RU-TA", name: "Республика Татарстан")
    @tatarstan_employee = User.create!(name: "Tatarstan Employee", email_address: "tatarstan@example.test",
      password: "test-password", manager: @manager, region:)
    @other_employee = User.create!(name: "Other Employee", email_address: "other-region@example.test",
      password: "test-password", manager: @manager)
    RegionalCalendar.create!(region:, year: 2026, legal_basis: "Закон Республики Татарстан", complete: true,
      public_holidays: [ Date.new(2026, 11, 6) ])
  end

  test "personal calendar marks the employee's regional holiday" do
    sign_in_as(@tatarstan_employee)

    get calendar_path(year: 2026, month: 11)

    assert_response :success
    assert_select ".personal-month__day[data-date='2026-11-06'].is-off", count: 1
  end

  test "team calendar marks the regional holiday only in the matching employee row" do
    sign_in_as(@manager)

    get manager_calendar_path(year: 2026, month: 11)

    assert_response :success
    assert_select ".team-timeline__date:nth-child(6):not(.is-off)", count: 1
    assert_select ".team-timeline__track[aria-label='Отсутствия: Tatarstan Employee'] " \
      ".team-timeline__day:nth-child(6).is-off", count: 1
    assert_select ".team-timeline__track[aria-label='Отсутствия: Other Employee'] " \
      ".team-timeline__day:nth-child(6):not(.is-off)", count: 1
  end
end
