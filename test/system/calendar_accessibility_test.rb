require "test_helper"

class CalendarAccessibilityTest < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 844 ]

  test "calendars show readable event text on narrow screens" do
    manager = User.create!(name: "Test Manager", email_address: "manager@example.test",
      password: "test-password", role: :manager)
    employee = User.create!(name: "Test Employee", email_address: "employee@example.test",
      password: "test-password", manager:, birthday_on: Date.new(1990, 10, 20))
    leave_type = LeaveType.create!(name: "Test leave", code: "TEST_A11Y")
    approved = LeaveRequest.create!(employee:, leave_type:, starts_on: Date.new(2026, 10, 20),
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

    assert_selector "td.leave[aria-label*='Согласовано']", text: "С"
    assert_selector "td.leave-pending[aria-label*='На рассмотрении']", text: "Р"
    assert_mobile_calendar_layout
    assert_operator contrast_ratio("td.leave"), :>=, 4.5
    assert_operator contrast_ratio("td.leave-pending"), :>=, 4.5

    click_button "Выйти"
    fill_in "Электронная почта", with: manager.email_address
    fill_in "Пароль", with: "test-password"
    click_button "Войти"
    assert_button "Выйти"
    visit manager_calendar_path(year: 2026, month: 10)

    assert_selector ".team-timeline__bar[aria-label*='Согласовано']", text: "Test leave"
    assert_selector ".team-timeline__birthday[aria-label*='день рождения']", text: "ДР"
    assert_in_delta 5, page.evaluate_script("Array.from(document.querySelectorAll('.team-timeline__bar')).find(bar => bar.getAttribute('aria-label').includes('09:00')).getBoundingClientRect().width"), 1
    assert_mobile_timeline_layout
    assert_operator contrast_ratio(".team-timeline__bar"), :>=, 4.5
    assert_operator contrast_ratio(".team-timeline__birthday"), :>=, 4.5
  end

  private

  def assert_mobile_calendar_layout
    [ 320, 375, 390, 768 ].each do |width|
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
        width:, height: 844, deviceScaleFactor: 1, mobile: false)

      assert_equal width, page.evaluate_script("window.innerWidth")
      assert_operator calendar_scroll_width, :>, calendar_client_width,
        "calendar should scroll horizontally at #{width}px"
      assert_operator calendar_day_width, :>=, 30,
        "calendar days should remain readable at #{width}px"
      assert_operator scroll_calendar, :>, 0,
        "calendar should be horizontally scrollable at #{width}px"
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

  def calendar_scroll_width
    page.evaluate_script("document.querySelector('.team-calendar-wrap').scrollWidth")
  end

  def calendar_client_width
    page.evaluate_script("document.querySelector('.team-calendar-wrap').clientWidth")
  end

  def calendar_day_width
    page.evaluate_script("document.querySelector('.team-calendar--month thead tr:last-child th').getBoundingClientRect().width")
  end

  def scroll_calendar
    page.evaluate_script("(() => { const wrapper = document.querySelector('.team-calendar-wrap'); wrapper.scrollLeft = 100; return wrapper.scrollLeft })()")
  end

  def contrast_ratio(selector)
    colors = page.evaluate_script(<<~JAVASCRIPT)
      (() => {
        const style = getComputedStyle(document.querySelector(#{selector.to_json}));
        return [style.color, style.backgroundColor];
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
