ActiveRecord::Base.transaction do
  [
    { code: "ANNUAL", name: "Ежегодный отпуск", holiday_handling: :exclude_public_holidays },
    { code: "BIRTHDAY", name: "Выходной в день рождения",
      holiday_handling: :include_public_holidays },
    { code: "SICK", name: "Больничный", holiday_handling: :include_public_holidays },
    { code: "UNPAID", name: "Отпуск без сохранения заработной платы",
      holiday_handling: :include_public_holidays }
  ].each do |attributes|
    leave_type = LeaveType.find_or_initialize_by(code: attributes.fetch(:code))
    leave_type.update!(attributes.merge(active: true))
  end

  next unless Rails.env.development?

  password = ENV.fetch("DEV_SEED_PASSWORD", "development-password")

  administrator = User.find_or_initialize_by(email_address: "admin@leave-desk.test")
  administrator.update!(name: "Администратор", role: :administrator, active: true,
    password:)

  manager = User.find_or_initialize_by(email_address: "manager@leave-desk.test")
  manager.update!(name: "Руководитель", role: :manager, active: true, password:)

  employee = User.find_or_initialize_by(email_address: "employee@leave-desk.test")
  employee.update!(name: "Сотрудник", role: :employee, manager:, active: true,
    password:)

  demo_names = [
    "Алексей Воронцов", "Анна Белова", "Борис Орлов", "Вера Соколова",
    "Глеб Морозов", "Дарья Волкова", "Евгений Лебедев", "Жанна Павлова",
    "Илья Козлов", "Кира Новикова", "Лев Фёдоров", "Мария Алексеева",
    "Никита Попов", "Ольга Семёнова", "Павел Егоров", "Раиса Макарова",
    "Сергей Захаров", "Тамара Виноградова", "Фёдор Николаев", "Юлия Громова"
  ]
  annual_leave = LeaveType.find_by!(code: "ANNUAL")
  calendar_year = Date.current.year

  demo_names.each_with_index do |name, index|
    demo_employee = User.find_or_initialize_by(email_address: "employee#{index + 1}@leave-desk.test")
    demo_employee.update!(name:, role: :employee, manager:, active: true, password:,
      birthday_on: Date.new(1990, (index % 12) + 1, ((index * 3) % 27) + 1))

    starts_on = Date.new(calendar_year, (index % 12) + 1, 10) + (index % 4).days
    ends_on = starts_on + 6.days
    request = LeaveRequest.find_or_initialize_by(employee: demo_employee,
      leave_type: annual_leave, starts_on:, ends_on:)
    next if request.persisted?

    request.employee_comment = "Демонстрационный календарь"
    request.save!
    request.approve!(by: manager, comment: "Демонстрационные данные")
  end
end
