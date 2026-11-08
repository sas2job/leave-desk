require "digest"
require Rails.root.join("db/seeds/development_calendar")

class StagingCalendar2027
  YEAR = 2027
  DATES = Date.new(YEAR, 1, 1)..Date.new(YEAR, 12, 31)
  class UnsafeData < StandardError; end

  def preview
    generate(commit: false)
  end

  def apply!(expected_digest:)
    generate(commit: true, expected_digest:)
  end

  private

  def generate(commit:, expected_digest: nil)
    result = nil
    User.transaction(requires_new: true) do
      employees = User.where(role: :employee, active: true).includes(:manager).order(:id).to_a
      employees.each(&:lock!) if commit
      validate_roster!(employees)
      original_requests = requests_for(employees).to_a
      before = statistics(employees, original_requests)
      snapshot = [ employees.map { |employee| employee.attributes.slice("id", "email_address", "birthday_on", "manager_id", "region_id", "updated_at") },
        employees.map { |employee| [ employee.manager.id, employee.manager.role, employee.manager.active? ] },
        original_requests.map(&:attributes), FederalCalendar.find_by!(year: YEAR).attributes,
        RegionalCalendar.where(year: YEAR).order(:region_id).map(&:attributes),
        LeaveType.where(code: %w[ANNUAL BIRTHDAY]).order(:code).map(&:attributes) ].to_json
      filled_birthdays = []
      employees.each do |employee|
        next if employee.birthday_on.present?

        employee.update!(birthday_on: fallback_birthday(employee))
        filled_birthdays << [ employee.id, employee.birthday_on ]
      end
      DevelopmentCalendarSeed.new(year: YEAR, employees:, staging: true).call
      all_requests = requests_for(employees).to_a
      new_requests = all_requests.reject { |request| original_requests.any? { |original| original.id == request.id } }
      logical_rows = new_requests.map do |request|
        [ request.employee_id, request.leave_type.code, request.starts_on, request.ends_on,
          request.start_minute, request.end_minute, request.duration_minutes, request.employee_comment ]
      end.sort_by { |row| [ row[0], row[1], row[-1] ] }
      digest = Digest::SHA256.hexdigest([ snapshot, filled_birthdays, logical_rows ].to_json)
      changed = new_requests.any? || filled_birthdays.any?
      raise UnsafeData, "План 2027 изменился; повторите предварительную проверку" if commit && changed && expected_digest != digest

      result = { year: YEAR, employees: employees.size, before:, after: statistics(employees, all_requests),
        added_requests: new_requests.size, filled_birthdays: filled_birthdays.size,
        plan_digest: digest, already_applied: !changed }
      result[:applied] = true if commit && changed
      raise ActiveRecord::Rollback unless commit
    end
    result
  end

  def validate_roster!(employees)
    raise UnsafeData, "Нет активных сотрудников" if employees.empty?
    unless employees.all? { |employee| employee.email_address.end_with?("@leave-desk.test") }
      raise UnsafeData, "В выбранной группе есть адрес вне демонстрационного домена"
    end
    unless employees.all? { |employee| employee.manager&.active? && employee.manager.manager? && employee.manager_id != employee.id }
      raise UnsafeData, "У каждого сотрудника должен быть активный руководитель"
    end
    raise UnsafeData, "Федеральный календарь 2027 не настроен" unless FederalCalendar.exists?(year: YEAR)
    confirmed_regions = RegionalCalendar.where(year: YEAR, complete: true).pluck(:region_id)
    unless employees.all? { |employee| employee.region_id.nil? || confirmed_regions.include?(employee.region_id) }
      raise UnsafeData, "Региональные календари 2027 требуют подтверждения"
    end
    unless LeaveType.where(code: %w[ANNUAL BIRTHDAY], active: true).count == 2
      raise UnsafeData, "Виды ANNUAL и BIRTHDAY должны быть активны"
    end
  end

  def fallback_birthday(employee)
    random = Random.new(2_027_000 + employee.id)
    loop do
      birthday = Date.ordinal(1990, random.rand(1..365))
      occurrence = Date.new(YEAR, birthday.month, birthday.day)
      day_off = FederalCalendar.nonworking_dates([ occurrence ], region_id: employee.region_id).include?(occurrence)
      leave_on = day_off ? occurrence.next_week(:wednesday) : occurrence
      return birthday if leave_on.year == YEAR
    end
  end

  def requests_for(employees)
    LeaveRequest.where(employee_id: employees.map(&:id))
      .where("starts_on <= ? AND ends_on >= ?", DATES.last, DATES.first).includes(:leave_type).order(:id)
  end

  def statistics(employees, requests)
    rows = employees.map do |employee|
      approved = requests.select { |request| request.employee_id == employee.id && request.approved_or_recalled? }
      { employee:, leave_days: approved.flat_map { |request| ([ request.starts_on, DATES.first ].max..[ request.effective_ends_on, DATES.last ].min).to_a }.to_set }
    end
    dates = DATES.to_a
    coverage = dates.index_with { |date| rows.count { |row| row[:leave_days].include?(date) } }
    report = TeamCalendarOverlapReport.new(rows:, coverage:, dates:)
    { employees_without_birthday: employees.count { |employee| employee.birthday_on.blank? },
      request_counts: requests.group_by { |request| request.leave_type.code }.transform_values { |group| group.group_by(&:status).transform_values(&:size) },
      employees_with_two_approved_annual: employees.count do |employee|
        requests.count { |request| request.employee_id == employee.id && request.annual_leave? && request.approved? } >= 2
      end,
      employees_with_approved_birthday: employees.count do |employee|
        requests.any? { |request| request.employee_id == employee.id && request.leave_type.code == "BIRTHDAY" && request.approved? }
      end,
      overlap_months: report.months.map { |month| month[:month] }, overlap_days: report.overlap_days,
      max_daily_absent: coverage.values.max }
  end
end

if ENV.key?("DEMO_CALENDAR_MODE")
  begin
    generator = StagingCalendar2027.new
    result = case ENV.fetch("DEMO_CALENDAR_MODE")
    when "plan" then generator.preview
    when "apply" then generator.apply!(expected_digest: ENV.fetch("DEMO_CALENDAR_PLAN_DIGEST"))
    else raise StagingCalendar2027::UnsafeData, "Неизвестный режим"
    end
    puts result.to_json
  rescue StagingCalendar2027::UnsafeData => error
    abort error.message
  rescue StandardError => error
    abort "Подготовка 2027 года не выполнена (#{error.class})"
  end
end
