require "test_helper"

class LeaveRequestDatePickerTest < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 844 ]

  test "date picker starts in 2025 and allows only current or future dates" do
    travel_to Date.new(2026, 10, 28) do
      employee = User.create!(name: "Test Employee", email_address: "employee@example.test",
        password: "test-password")

      visit new_session_path
      fill_in "Электронная почта", with: employee.email_address
      fill_in "Пароль", with: "test-password"
      click_button "Войти"
      assert_button "Выйти"
      visit leave_requests_path
      click_link "Создать заявку", match: :first

      first("[data-date-picker-button]").click
      within "dialog[open]" do
        assert_selector "select[data-calendar-year] option", text: "2025"
        assert_no_selector "select[data-calendar-year] option", text: "1976"

        select "2025", from: "Год"
        assert_selector "button.date-entry__day:disabled"

        select "2026", from: "Год"
        select "Октябрь", from: "Месяц"
        assert_selector "button.date-entry__day:disabled", text: "27"
        click_button "28"
      end

      assert_field "Дата начала", with: "28.10.2026"
    end
  end

  test "planner explains full annual leave and a partial first day" do
    travel_to Date.new(2026, 10, 28) do
      employee = User.create!(name: "Test Employee", email_address: "employee@example.test",
        password: "test-password")
      LeaveType.find_by!(code: "ANNUAL")

      visit new_session_path
      fill_in "Электронная почта", with: employee.email_address
      fill_in "Пароль", with: "test-password"
      click_button "Войти"
      assert_button "Выйти"
      visit leave_requests_path
      click_link "Создать заявку", match: :first

      assert_checked_field "leave_request_full_day"
      assert_no_selector "[data-workday-preset]"
      select "Ежегодный отпуск", from: "Вид отпуска"
      fill_in "Дата начала", with: "01.11.2026"
      fill_in "Дата окончания", with: "29.11.2026"
      assert_selector "[data-planner-summary]", text: "29 календарных дат · 28 дней отпуска"
      assert_selector ".leave-planner__day.is-excluded time[datetime='2026-11-04']"
      assert_no_selector "[data-time-field]", visible: true

      uncheck "leave_request_full_day"
      select "13:00", from: "Время начала"
      fill_in "Дата начала", with: "05.11.2026"
      fill_in "Дата окончания", with: "07.11.2026"
      assert_selector "[data-planner-summary]", text: /3 календарные даты.*крайние дни/
      assert_selector ".leave-planner__day:first-child", text: /с 13:00/
      assert_selector ".leave-planner__day:last-child", text: /до 18:00/

      check "leave_request_full_day"
      fill_in "Дата окончания", with: "11.11.2026"
      assert_selector "[data-planner-summary]", text: "7 календарных дат · 7 дней отпуска"
      assert_selector ".leave-planner__day", count: 7
    end
  end
end
