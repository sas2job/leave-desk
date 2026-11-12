require "active_support/testing/time_helpers"

class StagingDemoScenarios
  include ActiveSupport::Testing::TimeHelpers
  YEARS = [ 2026, 2027 ].freeze

  def call(users:)
    @types = LeaveType.where(code: %w[ANNUAL BIRTHDAY SICK]).index_by(&:code)
    employees = users.select(&:employee?)
    users.each_with_index do |user, index|
      if user.employee?
        user.update!(extended_annual_leave: index.odd?, annual_base_days: index.odd? ? 30 : 28,
          annual_additional_days: index % 4 >= 2 ? 3 : 0, annual_leave_basis: "Демонстрационная продолжительность отпуска")
      end
      [ 2025, *YEARS ].each do |year|
        days = user.annual_default_days(on: Date.new(year, 1, 1))
        AnnualLeaveYear.create!(employee: user, recorded_by: user.manager || user, starts_on: Date.new(year, 1, 1),
          ends_on: Date.new(year, 12, 31), entitlement_days: days, opening_used_days: year == 2025 ? days - 4 : 0,
          history_confirmed: true, basis: "Демонстрационный рабочий год")
      end
    end
    travel_to Time.zone.local(2026, 1, 1, 12) do
      employees.each_with_index do |employee, index|
        @employee = employee
        birthday_request(2026)
        annual_request(Date.new(2026, index % 10 + 1, 10 + index % 3), 7)
        annual_request(Date.new(2026, 12, 15 + index % 5), 2, approve: false)
        sick_request(index)
      end
    end
    travel_to Time.zone.local(2027, 1, 1, 12) do
      employees.each_with_index do |employee, index|
        @employee = employee
        birthday_request(2027)
        month = index % 6 + 1
        [ month, month + 6 ].each { |value| annual_request(Date.new(2027, value, 12 + index / 6 % 3), 7) }
      end
    end
  end

  private

  def birthday_request(year)
    occurrence = @employee.birthday_in_year(year) || Date.new(year, 6, 15)
    first, last = available(occurrence, 1, working_day: true)
    request = LeaveRequest.create!(employee: @employee, leave_type: @types.fetch("BIRTHDAY"), starts_on: first, ends_on: last,
      employee_comment: "Демонстрационный выходной в день рождения")
    request.approve!(by: @employee.manager)
  end

  def annual_request(preferred, length, approve: true)
    first, last = available(preferred, length)
    request = LeaveRequest.new(employee: @employee, leave_type: @types.fetch("ANNUAL"), starts_on: first, ends_on: last,
      employee_comment: "Демонстрационный ежегодный отпуск")
    raise ActiveRecord::RecordInvalid, request unless request.submit
    return unless approve
    request.approve!(by: @employee.manager, legal_review: { conditions_confirmed: true,
      working_year_starts_on: first.beginning_of_year, working_year_ends_on: first.end_of_year,
      entitlement_days: @employee.annual_default_days(on: first.beginning_of_year) })
  end

  def sick_request(index)
    preferred = index % 3 == 2 ? Date.new(2026, 11, 20) : Date.new(2026, 10, 20)
    first, last = available(preferred + index % 5, 3)
    request = LeaveRequest.new(employee: @employee, leave_type: @types.fetch("SICK"), starts_on: first, ends_on: last,
      employee_comment: "Демонстрационный учёт отсутствия по болезни")
    raise ActiveRecord::RecordInvalid, request unless request.submit
    return if index % 3 == 2
    request.approve!(by: @employee.manager)
    return unless index % 3 == 0
    original_time = Time.current
    travel_to last.end_of_day
    request.close_sick_leave!(by: @employee, closed_on: last)
  ensure
    travel_to original_time if original_time
  end

  def available(preferred, length, working_day: false)
    limits = Date.new(preferred.year, 1, 1)..Date.new(preferred.year, 12, 31)
    occupied = @employee.leave_requests.where(status: %i[pending approved recalled interrupted]).map do |request|
      request.starts_on..request.effective_ends_on
    end
    candidate = (limits.first..(limits.last - length + 1)).sort_by { |date| (date - preferred).abs }.find do |date|
      next false if working_day && FederalCalendar.nonworking_dates([ date ], region_id: @employee.region_id).include?(date)
      occupied.none? { |period| date <= period.last && date + length - 1 >= period.first }
    end
    raise "Недостаточно свободных дат для демонстрационного набора" unless candidate
    [ candidate, candidate + length - 1 ]
  end
end
