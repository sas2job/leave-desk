require "digest"
require Rails.root.join("db/seeds/staging_demo_scenarios")

class StagingDemoReseed
  class UnsafeData < StandardError; end
  DOMAIN = "%@leave-desk.test"
  YEARS = [ 2026, 2027 ].freeze

  def initialize(scenarios: StagingDemoScenarios.new)
    @scenarios = scenarios
  end

  def preview
    generate(commit: false)
  end

  def apply!(expected_digest:)
    generate(commit: true, expected_digest:)
  end

  private

  def generate(commit:, expected_digest: nil)
    raise UnsafeData, "Операция разрешена только для staging или тестов" unless Rails.env.production? || Rails.env.test? || Rails.env.development?
    result = nil
    LeaveRequest.transaction(requires_new: true) do
      LeaveType.order(:id).lock.load
      FederalCalendar.with_year_locks(YEARS) do
        User.connection.execute("SELECT pg_advisory_xact_lock(61370029)")
        ids = User.where(active: true).where("email_address LIKE ?", DOMAIN).order(:id).pluck(:id)
        LeaveRequest.where(employee_id: ids).order(:id).lock.load
        users = User.where(id: ids).order(:id).lock.includes(:manager).to_a
        validate!(users)
        identities = user_identities
        session_ids = Session.order(:id).pluck(:id)
        calendars = calendar_snapshot
        tables = activity_tables(ids)
        archive = tables.transform_values { |relation| relation.order(:id).map(&:attributes).as_json }
        raise UnsafeData, "Слишком много записей для демонстрационного пересоздания" if archive.fetch("leave_requests").size > 10_000
        source = [ archive, users.map(&:attributes), identities, calendars, DemoSeedArchive.count ]
        digest = Digest::SHA256.hexdigest([ "demo-balances-v1", source ].as_json.to_json)
        if commit && digest != expected_digest
          raise UnsafeData, "План устарел: данные изменились после предварительного просмотра"
        end
        before = archive.transform_values(&:size)
        clear_activity!(tables)
        @scenarios.call(users:)
        passwords_unchanged = identities == user_identities
        sessions_unchanged = session_ids == Session.order(:id).pluck(:id)
        calendars_unchanged = calendars == calendar_snapshot
        raise UnsafeData, "Изменились учётные записи, пароли, сессии или календари" unless passwords_unchanged && sessions_unchanged && calendars_unchanged
        result = { plan_digest: digest, users: users.size, employees: users.count(&:employee?), archived: before,
          after: verify!(users), passwords_unchanged:, sessions_unchanged:, calendars_unchanged:,
          archive_created: commit }
        DemoSeedArchive.create!(plan_digest: digest, archived_data: archive, summary: result) if commit
      end
      raise ActiveRecord::Rollback unless commit
    end
    result
  end

  def validate!(users)
    employees = users.select(&:employee?)
    raise UnsafeData, "Не найдены активные demo-сотрудники" if employees.empty?
    unless employees.all? { |user| user.manager&.active? && user.manager.manager? && user.manager_id != user.id }
      raise UnsafeData, "Для каждого demo-сотрудника нужен активный руководитель"
    end
    unless FederalCalendar.where(year: YEARS).count == YEARS.size && LeaveType.where(code: %w[ANNUAL BIRTHDAY SICK], active: true).count == 3
      raise UnsafeData, "Не настроены календари 2026/2027 или необходимые виды отсутствия"
    end
    users.each do |user|
      next unless user.region_id
      unless RegionalCalendar.where(region_id: user.region_id, year: YEARS, complete: true).count == YEARS.size
        raise UnsafeData, "Региональные календари demo-сотрудников должны быть подтверждены"
      end
    end
  end

  def user_identities
    User.uncached do
      User.order(:id).pluck(:id, :email_address, :name, :role, :active, :manager_id, :city, :time_zone, :birthday_on, :password_digest)
    end
  end

  def calendar_snapshot
    [ FederalCalendar.order(:id).map(&:attributes), RegionalCalendar.order(:id).map(&:attributes), LeaveType.order(:id).map(&:attributes) ]
  end

  def activity_tables(ids)
    requests = LeaveRequest.where(employee_id: ids)
    years = AnnualLeaveYear.where(employee_id: ids)
    events = LeaveRequestEvent.where(leave_request_id: requests.select(:id))
    {
      "notifications" => Notification.where(leave_request_event_id: events.select(:id)),
      "annual_leave_bookings" => AnnualLeaveBooking.where(leave_request_id: requests.select(:id)),
      "annual_leave_adjustments" => AnnualLeaveAdjustment.where(annual_leave_year_id: years.select(:id)),
      "sick_leave_extensions" => SickLeaveExtension.where(leave_request_id: requests.select(:id)),
      "leave_legal_reviews" => LeaveLegalReview.where(leave_request_id: requests.select(:id)),
      "leave_recalls" => LeaveRecall.where(leave_request_id: requests.select(:id)),
      "leave_request_events" => events,
      "leave_requests" => requests,
      "annual_leave_years" => years
    }
  end

  def clear_activity!(tables)
    # Resolve subqueries before deleting their parent rows.
    ids = tables.transform_values { |relation| relation.pluck(:id) }
    tables.each { |name, relation| relation.klass.where(id: ids.fetch(name)).delete_all }
  end

  def verify!(users)
    requests = LeaveRequest.where(employee_id: users.map(&:id))
    years = AnnualLeaveYear.where(employee_id: users.map(&:id))
    years.each do |year|
      reserved = year.annual_leave_bookings.where(status: 0).sum(:minutes)
      committed = year.annual_leave_bookings.where(status: 1).sum(:minutes)
      unless reserved == year.reserved_minutes && committed == year.committed_minutes && year.available_minutes >= 0
        raise UnsafeData, "Расход и остатки рабочего года не согласованы"
      end
    end
    employees = users.select(&:employee?)
    available = employees.map do |user|
      user.annual_leave_years.where("starts_on <= ?", Date.new(2026, 11, 12))
        .sum("entitlement_days::bigint * 1440 - opening_used_minutes - reserved_minutes - committed_minutes") / 1440.0
    end
    raise UnsafeData, "Демонстрационные остатки должны быть положительными и меньше 50 дней" unless available.all? { |value| value.positive? && value < 50 }
    { requests: requests.count, approved: requests.approved.count, pending: requests.pending.count,
      working_years: years.count, bookings: AnnualLeaveBooking.where(leave_request_id: requests.select(:id)).count,
      closed_sick: requests.where.not(sick_closed_on: nil).count,
      entitlement_groups: years.where(starts_on: Date.new(2026, 1, 1)).group(:entitlement_days).count,
      minimum_current_available_days: available.min, maximum_current_available_days: available.max }
  end
end

if ENV.key?("DEMO_RESEED_MODE")
  begin
    reseed = StagingDemoReseed.new
    result = case ENV.fetch("DEMO_RESEED_MODE")
    when "plan" then reseed.preview
    when "apply" then reseed.apply!(expected_digest: ENV.fetch("DEMO_RESEED_PLAN_DIGEST"))
    else raise StagingDemoReseed::UnsafeData, "Неизвестный режим пересоздания"
    end
    puts result.to_json
  rescue StagingDemoReseed::UnsafeData => error
    warn error.message
    exit 1
  rescue StandardError => error
    warn "Пересоздание demo-данных остановлено (#{error.class})"
    exit 1
  end
end
