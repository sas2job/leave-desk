require "test_helper"

class TeamGanttTest < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1366, 900 ]

  test "birthday and leave overlays keep December day backgrounds aligned" do
    manager = User.create!(name: "Calendar Manager", email_address: "alignment-manager@example.test",
      password: "test-password", role: :manager)
    employee = User.create!(name: "Calendar Employee", email_address: "alignment-employee@example.test",
      password: "test-password", manager:, birthday_on: Date.new(1990, 12, 3))
    type = LeaveType.create!(name: "Calendar leave", code: "TEST_ALIGNMENT")
    request = LeaveRequest.create!(employee:, leave_type: type,
      starts_on: Date.new(2026, 12, 10), ends_on: Date.new(2026, 12, 18))
    request.approve!(by: manager)

    visit new_session_path
    fill_in "Электронная почта", with: manager.email_address
    fill_in "Пароль", with: "test-password"
    click_button "Войти"
    assert_button "Выйти"

    [ 12, "all" ].each do |month|
      visit manager_calendar_path(year: 2026, month:)
      assert_selector ".team-timeline__birthday"
      assert_selector ".team-timeline__bar"
      differences = page.evaluate_script(<<~JAVASCRIPT)
        (() => {
          const dates = [...document.querySelectorAll('.team-timeline__date')];
          const days = [...document.querySelector('.team-timeline__track').querySelectorAll('.team-timeline__day')];
          return days.map((day, index) =>
            Math.abs(day.getBoundingClientRect().left - dates[index].getBoundingClientRect().left));
        })()
      JAVASCRIPT
      assert differences.all? { |difference| difference <= 1 }, "Day backgrounds shifted by up to #{differences.max}px (month: #{month})"
    end
  end

  test "annual gantt opens details and isolates overlap participants" do
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
    assert_button "Выйти"
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

  test "one hundred employees keep birthdays precise and overlap selection usable" do
    load Rails.root.join("db/seeds/federal_calendars.rb")
    manager = User.create!(name: "Large Manager", email_address: "large-manager@example.test",
      password: "test-password", role: :manager)
    type = LeaveType.find_by(code: "ANNUAL") || LeaveType.create!(name: "Annual leave", code: "ANNUAL")
    100.times do |index|
      employee = User.create!(name: format("Large %03d", index), email_address: "large-#{index}@example.test",
        password: "test-password", manager:, birthday_on: index.zero? ? Date.new(1990, 7, 18) : DemoBirthdayDates.for_index(index % 20))
      first = index < 3 ? Date.new(2027, 7, 10 + index * 2) : Date.new(2027, 9, 10 + index % 10)
      request = LeaveRequest.create!(employee:, leave_type: type, starts_on: first, ends_on: first + 6)
      request.approve!(by: manager, legal_review: { conditions_confirmed: true,
        working_year_starts_on: Date.new(2027, 1, 1), working_year_ends_on: Date.new(2027, 12, 31), entitlement_days: 28 })
    end
    visit new_session_path
    fill_in "Электронная почта", with: manager.email_address
    fill_in "Пароль", with: "test-password"
    click_button "Войти"
    assert_button "Выйти"
    visit manager_calendar_path(year: 2027, month: "all")
    assert_selector ".team-timeline__name", count: 100, visible: :all
    point_width, target_width, center_difference, bar_bottom, target_top = page.evaluate_script(<<~JAVASCRIPT)
      (() => {
        const marker = document.querySelector('.team-timeline--year .team-timeline__birthday');
        const target = marker.getBoundingClientRect();
        const date = document.querySelector('#team-year-date-2027-07-18').getBoundingClientRect();
        const bar = document.querySelector('.team-timeline__bar').getBoundingClientRect();
        return [parseFloat(getComputedStyle(marker, '::before').width), target.width,
          Math.abs((target.left + target.width / 2) - (date.left + date.width / 2)), bar.bottom, target.top];
      })()
    JAVASCRIPT
    assert_equal 3, point_width
    assert_operator target_width, :>=, 24
    assert_operator center_difference, :<=, 1
    assert_operator bar_bottom, :<=, target_top
    first("button.team-timeline__birthday").click
    assert_selector "dialog[open] h2", text: "День рождения"
    assert_selector "dialog[open]", text: /Large 000.*18\.07\.2027/
    within("dialog[open]") { click_button "Закрыть" }
    assert_no_selector "dialog[open]"
    first(".team-timeline__bar").click
    assert_selector "dialog[open] h2", text: "Период отсутствия"
    within("dialog[open]") { click_button "Закрыть" }
    assert_no_selector "dialog[open]"

    [ 320, 390, 768, 1366 ].each do |width|
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
        width:, height: 900, deviceScaleFactor: 1, mobile: false)
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, width
      assert_operator page.evaluate_script("document.querySelector('.team-timeline-wrap').scrollHeight"), :>,
        page.evaluate_script("document.querySelector('.team-timeline-wrap').clientHeight")
    end
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    select "14.07.2027–16.07.2027 · 3 чел.", from: "Пересечение по датам"
    click_button "Показать на шкале"
    assert_selector ".calendar-selection", text: /14\.07\.2027–16\.07\.2027/
    assert_selector ".team-timeline__name", count: 3, visible: :all
    assert_no_selector ".team-timeline__name", text: "Large 099", visible: :all
    click_link "Все сотрудники"
    assert_no_selector ".calendar-selection"
    assert_selector ".team-timeline__name", count: 100, visible: :all
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
