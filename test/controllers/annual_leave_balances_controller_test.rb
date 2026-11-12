require "test_helper"

class AnnualLeaveBalancesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @manager = User.create!(name: "Balance Manager", email_address: "balance-http-manager@example.test", password: "test-password", role: :manager)
    @employee = User.create!(name: "Balance Employee", email_address: "balance-http-employee@example.test", password: "test-password", manager: @manager)
    @other_manager = User.create!(name: "Other Manager", email_address: "balance-http-other@example.test", password: "test-password", role: :manager)
    @other = User.create!(name: "Other Employee", email_address: "balance-http-other-employee@example.test", password: "test-password", manager: @other_manager)
    @administrator = User.create!(name: "Balance Admin", email_address: "balance-http-admin@example.test", password: "test-password", role: :administrator)
  end

  test "manager sets up direct report balance and audits corrections" do
    sign_in_as(@manager)
    get manager_annual_leave_balances_path
    assert_response :success
    assert_select "h2", @employee.name
    assert_select "h2", text: @other.name, count: 0
    get manager_user_annual_leave_years_path(@employee)
    assert_response :success
    assert_select "h2", "Добавить рабочий год"
    assert_difference "AnnualLeaveYear.count", 1 do
      post manager_user_annual_leave_years_path(@employee), params: { annual_leave_year: attributes }
    end
    assert_response :redirect
    year = @employee.annual_leave_years.sole
    assert_equal @manager, year.recorded_by
    assert_equal 24 * 1440, year.available_minutes
    assert_difference "AnnualLeaveAdjustment.count", 1 do
      patch manager_user_annual_leave_year_path(@employee, year), params: { annual_leave_adjustment: {
        entitlement_days: "28", opening_used_days: "5", reason: "Повторная сверка" } }
    end
    assert_response :redirect
    assert_equal 23 * 1440, year.reload.available_minutes
    assert_equal @manager, year.annual_leave_adjustments.sole.actor
  end

  test "manager cannot edit self or another team and regular employees cannot configure balances" do
    sign_in_as(@manager)
    [ @manager, @other ].each do |user|
      get manager_user_annual_leave_years_path(user)
      assert_response :not_found
      assert_no_difference "AnnualLeaveYear.count" do
        post manager_user_annual_leave_years_path(user), params: { annual_leave_year: attributes }
        assert_response :not_found
      end
    end
    sign_in_as(@employee)
    get manager_annual_leave_balances_path
    assert_response :forbidden
    post admin_user_annual_leave_years_path(@employee), params: { annual_leave_year: attributes }
    assert_response :forbidden
  end

  test "manager configures only annual policy fields and legal minimums apply" do
    sign_in_as(@manager)
    patch manager_user_annual_leave_policy_path(@employee), params: { annual_policy: {
      extended_annual_leave: "1", annual_base_days: "28", annual_additional_days: "3", annual_leave_basis: "Установленная продолжительность" } }
    assert_response :redirect
    assert_equal 33, @employee.reload.annual_default_days
    patch manager_user_annual_leave_policy_path(@employee), params: { annual_policy: {
      extended_annual_leave: "1", annual_base_days: "30", annual_additional_days: "2", annual_leave_basis: "Основание" } }
    assert_response :redirect
    assert flash[:alert].present?
    assert_equal 33, @employee.reload.annual_default_days
    patch manager_user_annual_leave_policy_path(@employee), params: { annual_policy: { role: "administrator" } }
    assert_response :bad_request
    assert_predicate @employee.reload, :employee?
    patch manager_user_annual_leave_policy_path(@other), params: { annual_policy: {} }
    assert_response :not_found
  end

  test "administrator can configure every team but initial history confirmation is mandatory" do
    sign_in_as(@administrator)
    assert_no_difference "AnnualLeaveYear.count" do
      post admin_user_annual_leave_years_path(@other), params: { annual_leave_year: attributes.merge(history_confirmed: "0") }
      assert_response :unprocessable_entity
      assert_select ".error-summary"
    end
    post admin_user_annual_leave_years_path(@other), params: { annual_leave_year: attributes }
    assert_response :redirect
    assert_equal @administrator, @other.annual_leave_years.sole.recorded_by
  end

  test "own balance is isolated and setup page handles invalid dates and arrays" do
    configure_annual_year(@employee, used: 4)
    configure_annual_year(@other, used: 14)
    sign_in_as(@employee)
    get annual_leave_balance_path
    assert_response :success
    assert_select ".meta-value", text: "24 дн."
    assert_select ".meta-value", text: "14 дн.", count: 0
    sign_in_as(@manager)
    post manager_user_annual_leave_years_path(@employee), params: { annual_leave_year: attributes.merge(starts_on: "infinity") }
    assert_response :unprocessable_entity
    post manager_user_annual_leave_years_path(@employee), params: { annual_leave_year: attributes.merge(entitlement_days: [ "28" ]) }
    assert_response :bad_request
  end

  private

  def attributes
    { starts_on: "2026-01-01", ends_on: "2026-12-31", entitlement_days: "28", opening_used_days: "4", basis: "Сверка", history_confirmed: "1" }
  end
end
