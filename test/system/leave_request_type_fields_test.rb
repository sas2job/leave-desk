require "test_helper"

class LeaveRequestTypeFieldsTest < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome

  test "childcare fields and guidance follow the selected leave type" do
    employee = User.create!(name: "Form Employee", email_address: "type-form@example.test",
      password: "test-password")
    types = %w[ANNUAL MATERNITY CHILDCARE BIRTHDAY].index_with do |code|
      LeaveType.find_or_create_by!(code:) do |type|
        type.name = "Form #{code}"
        type.holiday_handling = :exclude_public_holidays if code == "ANNUAL"
      end
    end
    custom = LeaveType.create!(name: "Form custom leave", code: "TEST_TYPE_FIELDS")

    visit new_session_path
    fill_in "Электронная почта", with: employee.email_address
    fill_in "Пароль", with: "test-password"
    click_button "Войти"
    visit new_leave_request_path

    assert_no_selector "[data-childcare-field]"
    assert_no_selector "[data-leave-type-hint]"
    assert_no_selector "[data-partial-day-hint]"

    select types.fetch("CHILDCARE").name, from: "Вид отпуска"
    assert_selector "[data-childcare-field]", count: 2
    assert_field "leave_request_child_born_on", disabled: false
    assert_field "leave_request_care_relationship", disabled: false
    assert_selector "[data-leave-type-hint='#{types.fetch('CHILDCARE').id}']"
    assert_selector "[data-leave-type-hint]", count: 1

    %w[MATERNITY ANNUAL BIRTHDAY].each do |code|
      select types.fetch(code).name, from: "Вид отпуска"
      assert_no_selector "[data-partial-day-hint]"
      assert_selector "[data-period-guidance]", text: "Выберите полные календарные даты отпуска."
      assert_no_selector "[data-childcare-field]"
      assert_field "leave_request_child_born_on", disabled: true, visible: :all
      assert_field "leave_request_care_relationship", disabled: true, visible: :all
      assert_selector "[data-leave-type-hint='#{types.fetch(code).id}']"
      assert_selector "[data-leave-type-hint]", count: 1
      assert_no_selector "[data-period-field='ends_on']" if code == "BIRTHDAY"
    end

    select custom.name, from: "Вид отпуска"
    assert_selector "[data-partial-day-hint]", text: /Снимите отметку/
    assert_no_selector "[data-childcare-field]"
    assert_no_selector "[data-leave-type-hint]"
    assert_selector "[data-period-field='ends_on']"

    select types.fetch("CHILDCARE").name, from: "Вид отпуска"
    assert_selector "[data-childcare-field]", count: 2
    assert_field "leave_request_child_born_on", disabled: false
    assert_field "leave_request_care_relationship", disabled: false
  end
end
