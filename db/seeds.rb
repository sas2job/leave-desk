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
    if leave_type.new_record?
      leave_type.assign_attributes(attributes)
      leave_type.active = true
      leave_type.save!
    end
  end

  next unless Rails.env.development?

  load Rails.root.join("db/seeds/development.rb")
end
