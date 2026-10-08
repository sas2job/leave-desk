ActiveRecord::Base.transaction do
  [
    { code: "ANNUAL", name: "Ежегодный отпуск" },
    { code: "SICK", name: "Больничный" },
    { code: "UNPAID", name: "Отпуск без сохранения заработной платы" }
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
end
