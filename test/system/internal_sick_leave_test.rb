require "test_helper"

class InternalSickLeaveFormTest < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1366, 900 ]

  test "employee and manager extend and close a sick leave in its card" do
    manager = User.create!(name: "Flow Manager", email_address: "sick-flow-manager@example.test", password: "test-password", role: :manager)
    employee = User.create!(name: "Flow Employee", email_address: "sick-flow-employee@example.test", password: "test-password", manager:)
    type = LeaveType.find_or_create_by!(code: "SICK") { |type| type.name = "Больничный" }
    request = LeaveRequest.create!(employee:, leave_type: type, starts_on: Date.new(2026, 10, 1), ends_on: Date.new(2026, 10, 10))
    request.approve!(by: manager)
    login(employee)
    visit leave_requests_path
    assert_text "Требует уточнения"
    find("input[name='sick_leave[proposed_ends_on]']").set(Date.new(2026, 10, 20))
    click_button "Запросить продление"
    assert_text "Продление отправлено руководителю"
    assert_text "20.10.2026"
    assert_equal Date.new(2026, 10, 10), request.reload.ends_on
    using_session(:sick_manager) do
      login(manager)
      visit manager_leave_requests_path
      click_button "Подтвердить продление"
      assert_text "Продление подтверждено"
    end
    visit leave_requests_path
    assert_equal Date.new(2026, 10, 20), request.reload.ends_on
    [ 320, 390, 768, 1366 ].each do |width|
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height: 900, deviceScaleFactor: 1, mobile: false)
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, width
    end
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    find("input[name='sick_leave[closed_on]']").set(Date.new(2026, 10, 14))
    click_button "Закрыть больничный"
    assert_text "Больничный закрыт"
    assert_equal Date.new(2026, 10, 14), request.reload.sick_closed_on
    assert_no_button "Запросить продление"
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "one form supports past and cross year sick dates full days and a long period warning" do
    manager = User.create!(name: "Form Manager", email_address: "sick-form-manager@example.test", password: "test-password", role: :manager)
    employee = User.create!(name: "Form Employee", email_address: "sick-form-employee@example.test", password: "test-password", manager:)
    LeaveType.find_or_create_by!(code: "SICK") { |type| type.name = "Больничный" }
    LeaveType.find_or_create_by!(code: "UNPAID") { |type| type.name = "Без оплаты" }
    login(employee)
    visit new_leave_request_path
    select "Больничный", from: "Вид отпуска"
    assert_no_selector "[data-time-field]", visible: true
    assert_selector "[data-leave-type-hint]", text: /предполагаемое окончание/
    fill_in "Дата начала", with: "20.12.2025"
    fill_in "Дата окончания", with: "25.01.2026"
    assert_selector "[data-sick-long-warning]", text: /более 30/
    assert_equal "", find("#leave_request_ends_on").native.attribute("validationMessage")
    find("[data-period-field='starts_on'] [data-date-picker-button]").click
    assert_selector "dialog[open]"
    assert_selector "dialog[open] option[value='2025']:not([disabled])", visible: :all
    within("dialog[open]") { click_button "Закрыть" }
    click_button "Отправить заявку"
    assert_text "Мои заявки"
    assert_text "Ожидает подтверждения"
    assert_text "Длительный период"
    assert_equal 37, employee.leave_requests.sole.duration_in_days
  end

  private

  def login(user)
    visit new_session_path
    fill_in "Электронная почта", with: user.email_address
    fill_in "Пароль", with: "test-password"
    click_button "Войти"
    assert_current_path root_path
    assert_button "Выйти"
  end
end
