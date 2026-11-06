require "test_helper"

class LeaveRequestPeriodValidationTest < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome

  setup do
    travel_to Date.new(2026, 10, 14)
    @employee = User.create!(name: "Period Employee", email_address: "period-form@example.test",
      password: "test-password")
    @leave_type = LeaveType.create!(name: "Period form leave", code: "TEST_PERIOD_FORM")
    FederalCalendar.find_or_create_by!(year: 2026) do |calendar|
      calendar.legal_basis = "Test calendar"
      calendar.public_holidays = RussianFederalHoliday.fixed_dates_for(2026)
    end
    visit new_session_path
    fill_in "Электронная почта", with: @employee.email_address
    fill_in "Пароль", with: "test-password"
    click_button "Войти"
    assert_button "Выйти"
    visit new_leave_request_path
    select @leave_type.name, from: "Вид отпуска"
  end

  test "inverted period stays in the form and correction permits submission" do
    fill_in "Дата начала", with: "20.11.2026"
    fill_in "Дата окончания", with: "19.11.2026"
    assert_selector "#leave_request_ends_on_error", text: "Дата окончания раньше даты начала."
    assert_no_difference("@employee.leave_requests.count") { click_button "Отправить заявку" }
    assert_current_path new_leave_request_path
    assert_equal "leave_request_ends_on", page.evaluate_script("document.activeElement.id")

    fill_in "Дата окончания", with: "21.11.2026"
    assert_no_selector "#leave_request_ends_on_error"
    assert_difference("@employee.leave_requests.count", 1) do
      click_button "Отправить заявку"
      assert_current_path leave_requests_path
    end
  end

  test "impossible dates and out of range dates block submission" do
    fill_in "Дата начала", with: "30.11.2026"
    fill_in "Дата окончания", with: "31.11.2026"
    assert_selector "#leave_request_ends_on_error", text: /существующую дату/
    click_button "Отправить заявку"
    assert_current_path new_leave_request_path

    fill_in "Дата начала", with: "13.10.2026"
    fill_in "Дата окончания", with: "20.11.2026"
    assert_selector "#leave_request_starts_on_error", text: /допустимом периоде/
    click_button "Отправить заявку"
    assert_current_path new_leave_request_path
  end

  test "invalid hours clear when switching to full days" do
    fill_in "Дата начала", with: "20.11.2026"
    fill_in "Дата окончания", with: "20.11.2026"
    uncheck "leave_request_full_day"
    select "13:00", from: "Время начала"
    select "12:00", from: "Время окончания"
    assert_selector "#leave_request_end_time_error", text: /позже времени начала/
    click_button "Отправить заявку"
    assert_current_path new_leave_request_path

    check "leave_request_full_day"
    assert_no_selector "#leave_request_end_time_error"
    assert page.evaluate_script("document.querySelector('form[action$=\"/leave_requests\"]').checkValidity()")
  end
end
