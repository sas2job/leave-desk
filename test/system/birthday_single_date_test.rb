require "test_helper"

class BirthdaySingleDateTest < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome

  test "birthday uses one visible date and synchronizes picker and manual entry" do
    employee = User.create!(name: "Birthday Employee", email_address: "birthday-form@example.test", password: "test-password")
    LeaveType.find_or_create_by!(code: "BIRTHDAY") { |type| type.name = "Выходной в день рождения" }
    visit new_session_path
    fill_in "Электронная почта", with: employee.email_address
    fill_in "Пароль", with: "test-password"
    click_button "Войти"
    visit new_leave_request_path
    select "Выходной в день рождения", from: "Вид отпуска"
    assert_field "Дата выходного"
    assert_no_selector "[data-period-field='ends_on']", visible: true
    fill_in "Дата выходного", with: "20.10.2026"
    assert_field "leave_request_ends_on", with: "20.10.2026", visible: :all
    find("[data-period-field='starts_on'] [data-date-picker-button]").click
    click_button "21 октября 2026 г."
    assert_field "leave_request_ends_on", with: "21.10.2026", visible: :all
  end
end
