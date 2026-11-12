require_relative "demo_annual_balances"

password = ENV.fetch("DEV_SEED_PASSWORD", "development-password")

administrator = User.find_or_initialize_by(email_address: "admin@leave-desk.test")
administrator.city = "Москва" if administrator.city.blank?
administrator.password = password if administrator.new_record?
administrator.update!(name: "Администратор", role: :administrator, active: true)

manager = User.find_or_initialize_by(email_address: "manager@leave-desk.test")
manager.city = "Москва" if manager.city.blank?
manager.password = password if manager.new_record?
manager.update!(name: "Руководитель", role: :manager, active: true)

employee = User.find_or_initialize_by(email_address: "employee@leave-desk.test")
employee.city = "Москва" if employee.city.blank?
employee.password = password if employee.new_record?
employee.update!(name: "Сотрудник", role: :employee, manager:, active: true)

demo_names = [
  "Алексей Воронцов", "Анна Белова", "Борис Орлов", "Вера Соколова",
  "Глеб Морозов", "Дарья Волкова", "Евгений Лебедев", "Жанна Павлова",
  "Илья Козлов", "Кира Новикова", "Лев Фёдоров", "Мария Алексеева",
  "Никита Попов", "Ольга Семёнова", "Павел Егоров", "Раиса Макарова",
  "Сергей Захаров", "Тамара Виноградова", "Фёдор Николаев", "Юлия Громова"
]
demo_cities = [ "Москва", "Минск", "Братск" ] +
  (User::CITY_TIME_ZONES.keys - [ "Москва", "Минск", "Братск" ])
annual_leave = LeaveType.find_by!(code: "ANNUAL")
today = Date.current
[ administrator, manager, employee ].each { |person| DemoAnnualBalances.ensure!(person, today.year) }
remaining_days = (today.end_of_year - today).to_i + 1

demo_employees = demo_names.map.with_index do |name, index|
  demo_employee = User.find_or_initialize_by(email_address: "employee#{index + 1}@leave-desk.test")
  demo_employee.city = demo_cities[index % demo_cities.size] if demo_employee.city.blank?
  demo_employee.birthday_on ||= DemoBirthdayDates.for_index(index)
  if demo_employee.new_record?
    demo_employee.password = password
    demo_employee.assign_attributes(extended_annual_leave: index.odd?, annual_base_days: index.odd? ? 30 : 28,
      annual_additional_days: index % 4 >= 2 ? 3 : 0, annual_leave_basis: "Демонстрационные правила организации")
  end
  demo_employee.update!(name:, role: :employee, manager:, active: true)

  next demo_employee if demo_employee.leave_requests.exists?

  starts_on = today + (index % remaining_days).days
  ends_on = [ starts_on + 6.days, today.end_of_year ].min
  DemoAnnualBalances.ensure!(demo_employee, today.year)
  request = LeaveRequest.new(employee: demo_employee, leave_type: annual_leave,
    starts_on:, ends_on:)

  request.employee_comment = "Демонстрационный календарь"
  request.save!
  request.approve!(by: manager, comment: "Демонстрационные данные", legal_review: {
    conditions_confirmed: true, working_year_starts_on: today.beginning_of_year,
    working_year_ends_on: today.end_of_year, entitlement_days: demo_employee.annual_default_days(on: today.beginning_of_year)
  })
  demo_employee
end

require_relative "development_calendar"
DevelopmentCalendarSeed.new(year: 2027, employees: [ employee, *demo_employees ]).call
