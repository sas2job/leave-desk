require Rails.root.join("db/seeds/demo_annual_balances")
require "securerandom"
require "nokogiri"
require "rack/mock"

class StagingCalendarBenchmark2027
  class CheckFailed < StandardError; end

  def initialize(employee_count: 100)
    raise ArgumentError unless employee_count.between?(3, 100)

    @employee_count = employee_count
  end

  def call
    raise CheckFailed, "Календарь 2027 не настроен" unless FederalCalendar.exists?(year: 2027)
    annual = LeaveType.find_by!(code: "ANNUAL", active: true)
    baseline = counts
    result = nil
    user_ids = request_ids = event_ids = []
    User.transaction(requires_new: true) do
      prefix = "calendar-audit-#{SecureRandom.hex(6)}"
      digest = BCrypt::Password.create(SecureRandom.hex(24), cost: BCrypt::Engine::MIN_COST).to_s
      manager = User.create!(name: "Calendar audit manager", email_address: "#{prefix}-manager@leave-desk.test",
        password_digest: digest, role: :manager)
      user_ids = [ manager.id ]
      request_ids = @employee_count.times.map do |index|
        employee = User.create!(name: format("Calendar audit %03d", index),
          email_address: "#{prefix}-#{index}@leave-desk.test", password_digest: digest, manager:,
          birthday_on: Date.ordinal(1990, Random.new(2027 + index).rand(1..365)))
        user_ids << employee.id
        first = index < 3 ? Date.new(2027, 7, 10 + index * 2) : Date.new(2027, 9, 10 + index % 10)
        DemoAnnualBalances.ensure!(employee, 2027)
        request = LeaveRequest.create!(employee:, leave_type: annual, starts_on: first, ends_on: first + 6)
        request.approve!(by: manager, legal_review: { conditions_confirmed: true,
          working_year_starts_on: Date.new(2027, 1, 1), working_year_ends_on: Date.new(2027, 12, 31), entitlement_days: 28 })
        request.id
      end
      event_ids = LeaveRequestEvent.where(leave_request_id: request_ids).pluck(:id)
      result = { employees: @employee_count,
        year: render_calendar(manager, month: "all"),
        month: render_calendar(manager, month: "7"),
        selected_overlap: render_calendar(manager, month: "all", overlap_on: "2027-07-15") }
      unless result[:year][:employee_rows] == @employee_count && result[:month][:employee_rows] == @employee_count &&
          result[:selected_overlap][:employee_rows] == 3
        raise CheckFailed, "Неверное число строк полного или отфильтрованного календаря"
      end
      raise ActiveRecord::Rollback
    end
    rollback_verified = User.where(id: user_ids).none? && LeaveRequest.where(id: request_ids).none? &&
      LeaveRequestEvent.where(id: event_ids).none? && Notification.where(leave_request_event_id: event_ids).none?
    raise CheckFailed, "Откат контрольных данных не подтверждён" unless rollback_verified

    result.merge(rollback_verified:, before_counts: baseline, after_counts: counts)
  ensure
    Current.reset
  end

  private

  def counts
    { users: User.count, requests: LeaveRequest.count, events: LeaveRequestEvent.count,
      notifications: Notification.count, reviews: LeaveLegalReview.count, sessions: Session.count }
  end

  def render_calendar(manager, month:, overlap_on: nil)
    Current.session = Session.new(user: manager)
    query = { year: "2027", month:, overlap_on: }.compact.to_query
    env = Rails.application.env_config.merge(Rack::MockRequest.env_for("https://leave-desk.duckdns.org/manager/calendar?#{query}"))
    env["action_dispatch.request.path_parameters"] = { controller: "manager/calendars", action: "show" }
    env["action_dispatch.routes"] = Rails.application.routes
    env["HTTP_USER_AGENT"] = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36"
    app = ActionDispatch::Cookies.new(ActionDispatch::Session::CookieStore.new(
      Manager::CalendarsController.action(:show), Rails.application.config.session_options.dup))
    queries = 0
    subscriber = lambda do |*args|
      payload = args.last
      queries += 1 unless payload[:cached] || payload[:name] == "SCHEMA" || payload[:sql].match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/)
    end
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    body = nil
    status = content = nil
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      status, _, body = app.call(env)
      content = +""
      body.each { |chunk| content << chunk }
    end
    elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)
    raise CheckFailed, "Контрольный календарь вернул HTTP #{status}" unless status == 200

    document = Nokogiri::HTML(content)
    { employee_rows: document.css(".team-timeline__name").size,
      day_columns: document.css(".team-timeline__date").size, sql_queries: queries,
      milliseconds: elapsed, html_bytes: content.bytesize }
  ensure
    body&.close
    Current.reset
  end
end

if ENV.key?("DEMO_CALENDAR_MODE")
  begin
    raise StagingCalendarBenchmark2027::CheckFailed, "Контрольный запуск допускает только режим plan" unless ENV["DEMO_CALENDAR_MODE"] == "plan"
    puts StagingCalendarBenchmark2027.new.call.to_json
  rescue StandardError => error
    abort "Проверка большой команды не выполнена (#{error.class})"
  end
end
