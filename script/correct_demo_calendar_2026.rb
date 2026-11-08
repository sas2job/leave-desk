require "digest"
require "active_support/testing/time_helpers"

class DemoCalendarCorrection2026
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026
  MARKER = "Корректировка демо-календаря 2026: исходная заявка ".freeze
  ACTIVE_STATUSES = %i[pending approved recalled interrupted].freeze
  class UnsafeData < StandardError; end

  def initialize(expected_employees: 21, employee_emails: nil)
    @expected_employees = expected_employees
    @employee_emails = employee_emails
    @year_dates = Date.new(YEAR, 1, 1)..Date.new(YEAR, 12, 31)
  end

  def preview
    prepare
    return { already_applied: true, corrected_requests: @replacements.size } if @replacements.any?

    summary.merge(plan_digest: plan_digest)
  end

  def apply!(expected_digest:)
    LeaveRequest.transaction do
      prepare(lock: true)
      return { already_applied: true, corrected_requests: @replacements.size } if @replacements.any?
      raise UnsafeData, "План изменился; повторите предварительную проверку" unless expected_digest == plan_digest

      result = summary
      @sources.each { |source| source.cancel!(by: source.employee) }
      travel_to Time.zone.local(YEAR, 1, 1, 12) do
        @plan.each { |entry| create_replacement(entry) }
      end
      result.merge(applied: true, preserved_originals: @sources.size)
    end
  end

  private

  def prepare(lock: false)
    if @employee_emails
      raise UnsafeData, "Выбран адрес вне демонстрационного домена" if @employee_emails.any? { |email| !email.end_with?("@leave-desk.test") }
    elsif User.where.not("email_address LIKE ?", "%@leave-desk.test").exists?
      raise UnsafeData, "Обнаружены пользователи вне демонстрационного домена"
    end
    scope = User.where(active: true)
    scope = @employee_emails ? scope.where(email_address: @employee_emails) : scope.where(role: :employee)
    employees = scope.includes(:manager).order(:id).to_a
    unless employees.size == @expected_employees
      raise UnsafeData, "Неожиданное количество выбранных демо-сотрудников: #{employees.size}, ожидалось #{@expected_employees}"
    end
    @employee_count = employees.size
    unless employees.all? { |employee| employee.manager&.active? && employee.manager.manager? }
      raise UnsafeData, "Нужны активные руководители демонстрационной команды"
    end
    @replacements = LeaveRequest.where("employee_comment LIKE ?", "#{MARKER}%").to_a
    if @replacements.any?
      markers = @replacements.map { |request| request.employee_comment.match(/\A#{Regexp.escape(MARKER)}([1-9]\d*); пакет ([1-9]\d*)\z/) }
      unless markers.all? && markers.all? { |marker| marker[2].to_i == @replacements.size } &&
          @replacements.map(&:employee_id).uniq.size == @replacements.size &&
          (@replacements.map(&:employee_id) - employees.map(&:id)).empty?
        raise UnsafeData, "Обнаружена неполная предыдущая корректировка"
      end
      originals = LeaveRequest.where(id: markers.map { |marker| marker[1].to_i }).index_by(&:id)
      unless @replacements.zip(markers).all? do |request, marker|
        original = originals[marker[1].to_i]
        original&.cancelled? && original.employee_id == request.employee_id
      end
        raise UnsafeData, "Не подтверждена сохранённая история корректировки"
      end
      return
    end

    scope = LeaveRequest.joins(:leave_type).where(employee_id: employees.map(&:id), status: :approved,
      leave_types: { code: "ANNUAL" }, starts_on: @year_dates)
    @sources = scope.includes(:employee, :leave_type, :legal_review).order(:employee_id, :id).to_a
    @sources.each(&:lock!) if lock
    unless @sources.size.between?(@expected_employees - 1, @expected_employees) &&
        @sources.map(&:employee_id).uniq.size == @sources.size &&
        @sources.all? { |source| source.approved? && source.ends_on.year == YEAR && source.duration_in_days.positive? && source.leave_type.active? }
      raise UnsafeData, "Нужны #{@expected_employees - 1}–#{@expected_employees} согласованных ежегодных отпусков 2026 года, не более одного на сотрудника"
    end
    @sources, @untouched = @sources.partition { |source| source.full_calendar_days? && source.duration_in_days.to_i == source.duration_in_days }
    raise UnsafeData, "Нет поддерживаемых полных ежегодных отпусков для корректировки" if @sources.empty?
    @calendar = FederalCalendar.find_by!(year: YEAR)
    @regional = RegionalCalendar.where(year: YEAR).order(:region_id).index_by(&:region_id)
    @blocked = LeaveRequest.where(employee_id: employees.map(&:id), status: ACTIVE_STATUSES)
      .where.not(id: @sources.map(&:id)).where("starts_on <= ? AND ends_on >= ?", @year_dates.last, @year_dates.first)
      .order(:id).to_a
    random = Random.new(YEAR)
    months = (1..12).to_a.shuffle(random:)
    @plan = @sources.shuffle(random:).each_with_index.map do |source, index|
      preferred = Date.new(YEAR, months[index % 12], 10 + 2 * (index / 12))
      starts_on, ends_on = available_period(source, preferred)
      { source:, starts_on:, ends_on: }
    end
  end

  def available_period(source, preferred)
    holidays = (@calendar.public_holidays + (@regional[source.employee.region_id]&.public_holidays || [])).to_set
    blocked = @blocked.select { |request| request.employee_id == source.employee_id }
    @year_dates.sort_by { |date| (date - preferred).abs }.each do |starts_on|
      ends_on = starts_on
      days = 0
      while days < source.duration_in_days && ends_on <= @year_dates.last
        days += 1 unless holidays.include?(ends_on)
        ends_on += 1 if days < source.duration_in_days
      end
      next if ends_on > @year_dates.last
      next if blocked.any? { |request| starts_on <= request.effective_ends_on && ends_on >= request.starts_on }

      return [ starts_on, ends_on ]
    end
    raise UnsafeData, "Нет свободного периода с исходной продолжительностью"
  end

  def plan_digest
    rows = @plan.map do |entry|
      source = entry[:source]
      [ source.attributes, source.employee.attributes.slice("id", "birthday_on", "manager_id", "region_id"),
        entry[:starts_on], entry[:ends_on] ]
    end
    Digest::SHA256.hexdigest([ rows, @calendar.attributes, @regional.values.map(&:attributes), @blocked.map(&:attributes) ].to_json)
  end

  def summary
    before = (@sources + @untouched).map { |source| { source:, starts_on: source.starts_on, ends_on: source.ends_on } }
    untouched = @untouched.map { |source| { source:, starts_on: source.starts_on, ends_on: source.ends_on } }
    { year: YEAR, employees: @employee_count, correction_requests: @sources.size, unchanged_legacy: @untouched.size,
      without_approved_annual: @employee_count - before.size,
      before: period_summary(before), after: period_summary(@plan + untouched) }
  end

  def period_summary(entries)
    counts = @year_dates.map { |date| entries.count { |entry| (entry[:starts_on]..entry[:ends_on]).cover?(date) } }
    {
      months: entries.map { |entry| entry[:starts_on].month }.uniq.sort,
      birthday_month_matches: entries.count { |entry| entry[:source].employee.birthday_on&.month == entry[:starts_on].month },
      birthdays_inside_leave: entries.count do |entry|
        birthday = entry[:source].employee.birthday_in_year(YEAR)
        birthday && (entry[:starts_on]..entry[:ends_on]).cover?(birthday)
      end,
      overlap_days: counts.count { |count| count >= 2 }, max_daily_absent: counts.max
    }
  end

  def create_replacement(entry)
    source = entry[:source]
    request = LeaveRequest.create!(employee: source.employee, leave_type: source.leave_type,
      starts_on: entry[:starts_on], ends_on: entry[:ends_on], employee_comment: "#{MARKER}#{source.id}; пакет #{@sources.size}")
    request.approve!(by: source.employee.manager, comment: "Корректировка демонстрационных данных", legal_review: {
      conditions_confirmed: true, working_year_starts_on: @year_dates.first,
      working_year_ends_on: @year_dates.last, entitlement_days: source.legal_review&.entitlement_days || 28
    })
    raise UnsafeData, "Продолжительность отпуска изменилась" unless request.duration_in_days == source.duration_in_days
  end
end

if ENV.key?("DEMO_CALENDAR_MODE")
  begin
    seeded_emails = (1..20).map { |index| "employee#{index}@leave-desk.test" }
    puts({ preflight: { users_by_role: User.group(:role).count,
      active_employees: User.where(role: :employee, active: true).count,
      selected_seeded_employees: User.where(active: true, email_address: seeded_emails).count,
      selected_seeded_by_role: User.where(active: true, email_address: seeded_emails).group(:role).count,
      non_demo_users: User.where.not("email_address LIKE ?", "%@leave-desk.test").count } }.to_json)
    correction = DemoCalendarCorrection2026.new(expected_employees: 20, employee_emails: seeded_emails)
    result = case ENV.fetch("DEMO_CALENDAR_MODE")
    when "plan" then correction.preview
    when "apply" then correction.apply!(expected_digest: ENV.fetch("DEMO_CALENDAR_PLAN_DIGEST"))
    else raise DemoCalendarCorrection2026::UnsafeData, "Неизвестный режим"
    end
    puts result.to_json
  rescue DemoCalendarCorrection2026::UnsafeData => error
    abort error.message
  rescue StandardError => error
    abort "Корректировка не выполнена (#{error.class}); персональные данные не выводятся"
  end
end
