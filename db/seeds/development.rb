password = ENV.fetch("DEV_SEED_PASSWORD", "development-password")

administrator = User.find_or_initialize_by(email_address: "admin@leave-desk.test")
administrator.city = "Москва" if administrator.city.blank?
administrator.update!(name: "Администратор", role: :administrator, active: true,
  password:)

manager = User.find_or_initialize_by(email_address: "manager@leave-desk.test")
manager.city = "Москва" if manager.city.blank?
manager.update!(name: "Руководитель", role: :manager, active: true, password:)

employee = User.find_or_initialize_by(email_address: "employee@leave-desk.test")
employee.city = "Москва" if employee.city.blank?
employee.update!(name: "Сотрудник", role: :employee, manager:, active: true,
  password:)

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
remaining_days = (today.end_of_year - today).to_i + 1

demo_names.each_with_index do |name, index|
  demo_employee = User.find_or_initialize_by(email_address: "employee#{index + 1}@leave-desk.test")
  demo_employee.city = demo_cities[index % demo_cities.size] if demo_employee.city.blank?
  demo_employee.update!(name:, role: :employee, manager:, active: true, password:,
    birthday_on: Date.new(1990, (index % 12) + 1, ((index * 3) % 27) + 1))

  next if demo_employee.leave_requests.exists?

  starts_on = today + (index % remaining_days).days
  ends_on = [ starts_on + 6.days, today.end_of_year ].min
  request = LeaveRequest.new(employee: demo_employee, leave_type: annual_leave,
    starts_on:, ends_on:)

  request.employee_comment = "Демонстрационный календарь"
  request.save!
  request.approve!(by: manager, comment: "Демонстрационные данные")
end
