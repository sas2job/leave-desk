require "test_helper"

class TeamGanttTest < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome

  test "annual gantt opens details and isolates overlap participants" do
    travel_to Date.new(2026, 10, 1)
    manager = User.create!(name: "Gantt Manager", email_address: "gantt-manager@example.test",
      password: "test-password", role: :manager)
    employees = [ "First", "Second", "Unrelated" ].map do |name|
      User.create!(name: "Gantt #{name}", email_address: "gantt-#{name.downcase}@example.test",
        password: "test-password", manager:)
    end
    type = LeaveType.create!(name: "Gantt leave", code: "TEST_GANTT")
    [ [ employees[0], 14, 16 ], [ employees[1], 15, 17 ] ].each do |employee, first, last|
      request = LeaveRequest.create!(employee:, leave_type: type,
        starts_on: Date.new(2026, 10, first), ends_on: Date.new(2026, 10, last))
      request.approve!(by: manager)
    end

    visit new_session_path
    fill_in "Электронная почта", with: manager.email_address
    fill_in "Пароль", with: "test-password"
    click_button "Войти"
    visit manager_calendar_path(year: 2026, month: "all")
    assert_selector ".team-timeline--year"
    assert_selector ".team-timeline__name", count: 3
    first("[data-calendar-event]").click
    assert_selector "dialog[open]", text: /Gantt First.*14\.10\.2026.*16\.10\.2026/
    within("dialog[open]") { click_button "Закрыть" }

    select "15.10.2026–16.10.2026 · 2 чел.", from: "Пересечение по датам"
    click_button "Показать на шкале"
    assert_selector ".team-timeline__name", count: 2
    assert_no_selector ".team-timeline__name", text: "Gantt Unrelated"
    assert_selector ".calendar-selection", text: /15\.10\.2026–16\.10\.2026/
    click_link "Все сотрудники"
    assert_selector ".team-timeline__name", count: 3

    [ 320, 390, 768, 1366 ].each do |width|
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
        width:, height: 900, deviceScaleFactor: 1, mobile: false)
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, width
    end
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    within(".team-timeline__months") { click_link "октябрь" }
    assert_selector ".team-timeline__date", count: 31
    assert_no_selector ".team-timeline--year"
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
