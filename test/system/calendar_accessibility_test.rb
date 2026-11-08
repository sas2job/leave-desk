require "test_helper"

class CalendarAccessibilityTest < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 844 ]

  test "calendars align controls with other pages and keep events readable" do
    manager = User.create!(name: "Test Manager", email_address: "manager@example.test",
      password: "test-password", role: :manager)
    employee = User.create!(name: "Test Employee", email_address: "employee@example.test",
      password: "test-password", manager:, birthday_on: Date.new(1990, 10, 20))
    leave_type = LeaveType.create!(name: "Test leave", code: "TEST_A11Y")
    approved = LeaveRequest.create!(employee:, leave_type:, starts_on: Date.new(2026, 10, 16),
      ends_on: Date.new(2026, 10, 20))
    approved.approve!(by: manager)
    LeaveRequest.create!(employee:, leave_type:, starts_on: Date.new(2026, 10, 21),
      ends_on: Date.new(2026, 10, 21))
    partial = LeaveRequest.create!(employee:, leave_type:, starts_on: Date.new(2026, 10, 22),
      ends_on: Date.new(2026, 10, 22), start_time: "09:00", end_time: "12:00")
    partial.approve!(by: manager)

    visit new_session_path
    fill_in "Электронная почта", with: employee.email_address
    fill_in "Пароль", with: "test-password"
    click_button "Войти"
    assert_button "Выйти"
    visit calendar_path(year: 2026, month: 10)

    assert_selector ".personal-month__day.leave[aria-label*='Согласовано'] .calendar-event__short", text: "С"
    assert_selector ".personal-month__day.leave-pending[aria-label*='На рассмотрении'] .calendar-event__short", text: "Р"
    assert_selector ".calendar-legend", text: "Выходной или праздник"
    assert_selector ".personal-month__day.is-off.leave[data-date='2026-10-17'][aria-label*='Нерабочий день'] .calendar-event__short", text: "С"
    assert_operator contrast_ratio(".personal-month__day[data-date='2026-10-17'] .personal-month__date",
      background_selector: ".personal-month__day[data-date='2026-10-17']"), :>=, 4.5
    assert_standard_content_alignment(".calendar-page")
    assert_mobile_personal_layout
    assert_operator contrast_ratio(".calendar-event--approved"), :>=, 4.5
    assert_operator contrast_ratio(".calendar-event--pending"), :>=, 4.5

    visit calendar_path(year: 2026, month: "all")
    assert_selector ".personal-year__month", count: 12
    assert_selector ".personal-year__day.is-off.has-approved[data-date='2026-10-17'][aria-label*='Нерабочий день'] .personal-year__status", text: "С"
    assert_selector ".personal-year__day.is-off[data-date='2026-11-04']"
    [ "2026-10-17", "2026-10-25" ].each do |date|
      assert_operator contrast_ratio(".personal-year__day[data-date='#{date}'] time",
        background_selector: ".personal-year__day[data-date='#{date}']"), :>=, 4.5
    end
    assert_standard_content_alignment(".calendar-page")
    assert_personal_year_layout
    find(".personal-year__month h2 a[href='#{calendar_path(year: 2026, month: 10)}']").click
    assert_selector ".personal-month__day[data-date='2026-10-20']"

    click_button "Выйти"
    fill_in "Электронная почта", with: manager.email_address
    fill_in "Пароль", with: "test-password"
    click_button "Войти"
    assert_button "Выйти"
    visit manager_calendar_path(year: 2026, month: 10)

    assert_selector ".team-timeline__bar[aria-label*='Согласовано']", text: "Test leave"
    assert_selector ".team-timeline__birthday[aria-label*='день рождения']", text: "ДР"
    assert_standard_content_alignment(".team-calendar-controls")
    assert_team_diagram_width
    assert_in_delta 5, page.evaluate_script("Array.from(document.querySelectorAll('.team-timeline__bar')).find(bar => bar.getAttribute('aria-label').includes('09:00')).getBoundingClientRect().width"), 1
    assert_mobile_timeline_layout
    click_link "К первому отсутствию →"
    assert_operator page.evaluate_script("document.querySelector('.team-timeline-wrap').scrollLeft"), :>, 0
    assert_operator contrast_ratio(".team-timeline__bar"), :>=, 4.5
    assert_operator contrast_ratio(".team-timeline__birthday"), :>=, 4.5

    visit manager_calendar_path(year: 2026, month: "all")
    assert_selector ".team-timeline--year"
    assert_standard_content_alignment(".team-calendar-controls")
    assert_team_diagram_width
  end

  private

  def assert_standard_content_alignment(selector)
    [ 320, 375, 390, 500, 768, 1024, 1366, 1920 ].each do |width|
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
        width:, height: 900, deviceScaleFactor: 1, mobile: false)
      header_left, header_width, content_left, content_width = page.evaluate_script(<<~JAVASCRIPT)
        (() => {
          const header = document.querySelector('.site-header__inner').getBoundingClientRect();
          const content = document.querySelector(#{selector.to_json}).getBoundingClientRect();
          return [header.left, header.width, content.left, content.width];
        })()
      JAVASCRIPT
      assert_in_delta header_left, content_left, 1, "content should align with navigation at #{width}px"
      assert_in_delta header_width, content_width, 1, "content should share navigation width at #{width}px"
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, width
    end
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  def assert_team_diagram_width
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 1920, height: 900, deviceScaleFactor: 1, mobile: false)
    left, width = page.evaluate_script(<<~JAVASCRIPT)
      (() => {
        const diagram = document.querySelector('.team-timeline-wrap').getBoundingClientRect();
        return [diagram.left, diagram.width];
      })()
    JAVASCRIPT
    assert_in_delta 1540, width, 1
    assert_in_delta (1920 - width) / 2, left, 1
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  def assert_personal_year_layout
    [ 320, 375, 390, 768, 1366 ].each do |width|
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
        width:, height: 900, deviceScaleFactor: 1, mobile: false)
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, width
      assert_operator page.evaluate_script("document.querySelector('.personal-year__day').getBoundingClientRect().width"), :>=, 18
      assert_operator page.evaluate_script("parseFloat(getComputedStyle(document.querySelector('.personal-year__day')).fontSize)"), :>=, 12
    end
    assert_operator page.evaluate_script("document.querySelector('.personal-year__month:last-child').getBoundingClientRect().bottom"), :<=, 900
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  def assert_mobile_personal_layout
    [ 320, 375, 390, 768 ].each do |width|
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
        width:, height: 844, deviceScaleFactor: 1, mobile: false)

      assert_equal width, page.evaluate_script("window.innerWidth")
      assert_operator page.evaluate_script("document.querySelector('.personal-month__day[data-date]').getBoundingClientRect().width"), :>=, 40,
        "personal calendar days should remain readable at #{width}px"
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, width,
        "page should not scroll horizontally at #{width}px"
    end
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  def assert_mobile_timeline_layout
    [ 320, 375, 390, 768 ].each do |width|
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
        width:, height: 844, deviceScaleFactor: 1, mobile: false)
      assert_equal width, page.evaluate_script("window.innerWidth")
      assert_operator page.evaluate_script("document.querySelector('.team-timeline-wrap').scrollWidth"), :>,
        page.evaluate_script("document.querySelector('.team-timeline-wrap').clientWidth")
      assert_equal 40, page.evaluate_script("document.querySelector('.team-timeline__date').getBoundingClientRect().width")
      assert_operator page.evaluate_script("(() => { const wrap = document.querySelector('.team-timeline-wrap'); wrap.scrollLeft = 100; return wrap.scrollLeft })()"), :>, 0
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, width
    end
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  def contrast_ratio(selector, background_selector: selector)
    colors = page.evaluate_script(<<~JAVASCRIPT)
      (() => {
        const style = getComputedStyle(document.querySelector(#{selector.to_json}));
        const background = getComputedStyle(document.querySelector(#{background_selector.to_json}));
        return [style.color, background.backgroundColor];
      })()
    JAVASCRIPT
    luminances = colors.map do |color|
      channels = color.scan(/\d+/).first(3).map { |channel| channel.to_f / 255 }
      linear = channels.map { |channel| channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055)**2.4 }
      linear.zip([ 0.2126, 0.7152, 0.0722 ]).sum { |channel, weight| channel * weight }
    end
    (luminances.max + 0.05) / (luminances.min + 0.05)
  end
end
