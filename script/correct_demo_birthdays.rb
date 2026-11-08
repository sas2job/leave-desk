require "digest"
require Rails.root.join("lib/demo_birthday_dates")

class DemoBirthdayCorrection
  EMAILS = (1..20).map { |index| "employee#{index}@leave-desk.test" }.freeze
  class UnsafeData < StandardError; end

  def preview
    prepare
    result = summary
    result.merge(plan_digest:, already_applied: result[:changed_birthdays].zero?)
  end

  def apply!(expected_digest:)
    User.transaction do
      prepare(lock: true)
      result = summary
      return result.merge(already_applied: true) if result[:changed_birthdays].zero?
      raise UnsafeData, "План дат рождения изменился; повторите проверку" unless expected_digest == plan_digest

      @users.each do |user|
        user.update!(birthday_on: @targets.fetch(user.id)) if user.birthday_on != @targets.fetch(user.id)
      end
      @users.each(&:reload)
      result.merge(applied: true, actual_after: statistics(@users.to_h { |user| [ user.id, user.birthday_on ] }))
    end
  end

  private

  def prepare(lock: false)
    @users = User.where(email_address: EMAILS, active: true).order(:name, :id).to_a
    raise UnsafeData, "Ожидались 20 исходных демо-учётных записей" unless @users.size == EMAILS.size
    @users.each(&:lock!) if lock
    @targets = @users.to_h do |user|
      [ user.id, DemoBirthdayDates.for_index(EMAILS.index(user.email_address), year: user.birthday_on&.year || 1990) ]
    end
    @annual = LeaveRequest.joins(:leave_type).where(employee_id: @users.map(&:id),
      status: %i[approved recalled interrupted], leave_types: { code: "ANNUAL" })
      .where("starts_on <= ? AND ends_on >= ?", Date.new(2026, 12, 31), Date.new(2026, 1, 1)).to_a
  end

  def plan_digest
    Digest::SHA256.hexdigest(@users.map do |user|
      [ user.id, user.birthday_on, user.updated_at, @targets.fetch(user.id) ]
    end.to_json)
  end

  def summary
    { employees: @users.size, changed_birthdays: @users.count { |user| user.birthday_on != @targets.fetch(user.id) },
      before: statistics(@users.to_h { |user| [ user.id, user.birthday_on ] }), after: statistics(@targets) }
  end

  def statistics(dates)
    values = @users.filter_map do |user|
      date = dates.fetch(user.id)
      Date.new(2000, date.month, date.day).yday if date
    end
    increasing = decreasing = longest_increasing = longest_decreasing = 1
    values.each_cons(2) do |first, last|
      increasing = last >= first ? increasing + 1 : 1
      decreasing = last <= first ? decreasing + 1 : 1
      longest_increasing = [ longest_increasing, increasing ].max
      longest_decreasing = [ longest_decreasing, decreasing ].max
    end
    {
      missing_birthdays: dates.values.count(&:nil?),
      months: dates.values.compact.group_by(&:month).transform_values(&:size).sort.to_h,
      longest_increasing_run: longest_increasing, longest_decreasing_run: longest_decreasing,
      birthdays_inside_annual_leave_2026: @users.count do |user|
        date = dates.fetch(user.id)
        next false unless date
        next false unless Date.valid_date?(2026, date.month, date.day)

        birthday = Date.new(2026, date.month, date.day)
        @annual.any? { |request| request.employee_id == user.id && (request.starts_on..request.effective_ends_on).cover?(birthday) }
      end
    }
  end
end

if ENV.key?("DEMO_CALENDAR_MODE")
  begin
    correction = DemoBirthdayCorrection.new
    result = case ENV.fetch("DEMO_CALENDAR_MODE")
    when "plan" then correction.preview
    when "apply" then correction.apply!(expected_digest: ENV.fetch("DEMO_CALENDAR_PLAN_DIGEST"))
    else raise DemoBirthdayCorrection::UnsafeData, "Неизвестный режим"
    end
    puts result.to_json
  rescue DemoBirthdayCorrection::UnsafeData => error
    abort error.message
  rescue StandardError => error
    abort "Корректировка дат рождения не выполнена (#{error.class})"
  end
end
