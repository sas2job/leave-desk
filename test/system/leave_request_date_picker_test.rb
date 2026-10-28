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
      visit new_leave_request_path

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
end
