abort "Сначала требуется предварительный план" unless ENV["DEMO_CALENDAR_MODE"] == "plan"

employees = User.where(role: :employee, active: true).includes(:manager).order(:id).to_a
dates = Date.new(2027, 1, 1)..Date.new(2027, 12, 31)
requests = LeaveRequest.where(employee_id: employees.map(&:id))
  .where("starts_on <= ? AND ends_on >= ?", dates.last, dates.first).includes(:leave_type).to_a
federal = FederalCalendar.find_by(year: 2027)
regional = RegionalCalendar.where(year: 2027, complete: true).pluck(:region_id).to_set
puts({ year: 2027, employees: employees.size,
  employees_without_manager: employees.count { |employee| !employee.manager&.active? || !employee.manager.manager? },
  employees_without_birthday: employees.count { |employee| employee.birthday_on.blank? },
  non_demo_employees: employees.count { |employee| !employee.email_address.end_with?("@leave-desk.test") },
  federal_calendar_ready: federal.present?,
  public_holidays: federal&.public_holidays&.size, transfers: federal&.transfers&.size,
  employees_without_confirmed_calendar: employees.count { |employee| !federal || employee.region_id && !regional.include?(employee.region_id) },
  request_counts: requests.group_by { |request| request.leave_type.code }.transform_values { |rows| rows.group_by(&:status).transform_values(&:size) },
  approved_annual_distribution: employees.group_by { |employee| requests.count { |request| request.employee_id == employee.id && request.annual_leave? && request.approved? } }.transform_values(&:size),
  inactive_leave_types: LeaveType.where(code: %w[ANNUAL BIRTHDAY], active: false).pluck(:code)
}.to_json)
