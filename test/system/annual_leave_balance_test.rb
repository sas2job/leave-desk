require "test_helper"

class AnnualLeaveBalanceFormTest < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1366, 1000 ]

  test "manager configures balance and employee cannot send fifty days against twenty eight" do
    manager = User.create!(name: "Balance Form Manager", email_address: "balance-form-manager@example.test", password: "test-password", role: :manager)
    employee = User.create!(name: "Balance Form Employee", email_address: "balance-form-employee@example.test", password: "test-password", manager:)
    annual = LeaveType.find_or_create_by!(code: "ANNUAL") do |type|
      type.name = "Ежегодный отпуск"
      type.holiday_handling = :exclude_public_holidays
    end
    FederalCalendar.find_or_create_by!(year: 2026) do |calendar|
      calendar.legal_basis = "Тест"
      calendar.public_holidays = RussianFederalHoliday.fixed_dates_for(2026)
    end
    login(manager)
    visit manager_user_annual_leave_years_path(employee)
    fill_in "Начало рабочего года", with: Date.new(2026, 1, 1)
    fill_in "Окончание рабочего года", with: Date.new(2026, 12, 31)
    fill_in "Положено за рабочий год, дней", with: "28"
    fill_in "Учтено до настройки остатка, дней", with: "0"
    fill_in "Основание и дата сверки", with: "Кадровая сверка"
    check "annual_leave_year_history_confirmed"
    click_button "Сохранить рабочий год"
    assert_text "Рабочий год и начальный остаток сохранены"
    assert_equal 28, employee.annual_leave_years.sole.entitlement_days

    using_session(:balance_employee) do
      login(employee)
      visit annual_leave_balance_path
      assert_text "28 дн."
      visit new_leave_request_path
      select annual.name, from: "Вид отпуска"
      assert_text "Доступно на сегодня: 28 дн."
      fill_in "Дата начала", with: "12.11.2026"
      fill_in "Дата окончания", with: "31.12.2026"
      click_button "Отправить заявку"
      assert_selector ".error-summary", text: /Недостаточно дней/
      assert_equal 0, employee.leave_requests.count
      fill_in "Дата окончания", with: "25.11.2026"
      click_button "Отправить заявку"
      assert_current_path leave_requests_path
      assert_text "Зарезервировано по рабочим годам"
      visit annual_leave_balance_path
      assert_selector ".meta-value", text: "14 дн.", count: 2
      [ 320, 390, 768, 1366 ].each do |width|
        page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height: 1000, deviceScaleFactor: 1, mobile: false)
        assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, width
      end
      page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    end
  end

  test "increased entitlement checkbox selects thirty and irregular minimum is enforced" do
    manager = User.create!(name: "Policy Form Manager", email_address: "policy-form-manager@example.test", password: "test-password", role: :manager)
    employee = User.create!(name: "Policy Form Employee", email_address: "policy-form-employee@example.test", password: "test-password", manager:)
    login(manager)
    visit manager_user_annual_leave_years_path(employee)
    check "user_extended_annual_leave"
    assert_field "Основной отпуск, дней", with: "30"
    fill_in "За ненормированный день, дополнительно", with: "3"
    fill_in "Основание увеличения", with: "Установленная продолжительность"
    click_button "Сохранить продолжительность"
    assert_text "Продолжительность отпуска обновлена"
    assert_equal 33, employee.reload.annual_default_days
    assert_field "Положено за рабочий год, дней", with: "33"
  end

  private

  def login(user)
    visit new_session_path
    fill_in "Электронная почта", with: user.email_address
    fill_in "Пароль", with: "test-password"
    click_button "Войти"
    assert_current_path root_path
  end
end
