# Explicit fixture setup for the existing demo generators, never for real staff.
module DemoAnnualBalances
  def self.ensure!(employee, year)
    return if employee.annual_leave_years.where(starts_on: Date.new(year, 1, 1)).exists?

    historical = employee.leave_requests.joins(:leave_type)
      .where(leave_types: { code: "ANNUAL" }, status: %i[approved recalled])
      .where("starts_on >= ? AND starts_on <= ?", Date.new(year, 1, 1), Date.new(year, 12, 31))
      .where.not(id: AnnualLeaveBooking.select(:leave_request_id))
    used = historical.sum { |request| request.annual_requested_minutes }
    AnnualLeaveYear.create!(employee:, recorded_by: employee.manager || employee,
      starts_on: Date.new(year, 1, 1), ends_on: Date.new(year, 12, 31),
      entitlement_days: employee.annual_default_days(on: Date.new(year, 1, 1)),
      opening_used_minutes: used, history_confirmed: true, basis: "Демонстрационные данные: начальная сверка")
  end
end
