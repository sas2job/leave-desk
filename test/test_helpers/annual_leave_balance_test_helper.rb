module AnnualLeaveBalanceTestHelper
  def configure_annual_year(employee, year: 2026, days: 28, used: 0)
    employee.annual_leave_years.find_by(starts_on: Date.new(year, 1, 1)) ||
      AnnualLeaveYear.create!(employee:, recorded_by: employee.manager || employee,
        starts_on: Date.new(year, 1, 1), ends_on: Date.new(year, 12, 31),
        entitlement_days: days, opening_used_days: used, history_confirmed: true, basis: "Тестовая кадровая сверка")
  end
end
ActiveSupport::TestCase.include AnnualLeaveBalanceTestHelper
