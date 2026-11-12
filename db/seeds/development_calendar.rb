require_relative "demo_annual_balances"
require "active_support/testing/time_helpers"

class DevelopmentCalendarSeed
  include ActiveSupport::Testing::TimeHelpers

  def initialize(year:, employees:, staging: false)
    @year = year
    @employees = employees
    @staging = staging
    @dates = Date.new(year, 1, 1)..Date.new(year, 12, 31)
    @annual_leave = LeaveType.find_by!(code: "ANNUAL")
    @birthday_leave = LeaveType.find_by!(code: "BIRTHDAY")
    FederalCalendar.find_by!(year:)
  end

  def call
    staging_allowed = @staging && Rails.env.production? && @year == 2027 && @employees.any? &&
      @employees.all? { |employee| employee.persisted? && employee.active? && employee.employee? && employee.email_address.end_with?("@leave-desk.test") }
    unless Rails.env.development? || Rails.env.test? || staging_allowed
      raise "Демонстрационные данные доступны только в development, test или явной операции стенда 2027"
    end

    # Моделируем создание данных в начале целевого года, сохраняя проверки модели
    # для BIRTHDAY и штатные события создания и согласования.
    travel_to Time.zone.local(@year, 1, 1, 12) do
      LeaveRequest.transaction do
        @employees.each_with_index do |employee, index|
          DemoAnnualBalances.ensure!(employee, @year)
          if employee.birthday_on.blank?
            employee.update!(birthday_on: Date.new(1990, (index % 12) + 1, ((index * 3 + 15) % 27) + 1))
          end
          birthday = employee.birthday_in_year(@year)
          raise "Для демонстрационного календаря нужна дата рождения в выбранном году" unless birthday

          if FederalCalendar.nonworking_dates([ birthday ], region_id: employee.region_id).include?(birthday)
            birthday = birthday.next_week(:wednesday)
          end
          create_request(employee, @birthday_leave, "Выходной в день рождения") { [ birthday, birthday ] }

          first_month = index % 6 + 1
          [ first_month, first_month + 6 ].each_with_index do |month, part|
            create_request(employee, @annual_leave, "Ежегодный отпуск #{part + 1}", half: part) do
              available_period(employee, Date.new(@year, month, 10 + ((index / 6) % 4) * 2))
            end
          end
        end
      end
    end
  end

  private

  def create_request(employee, leave_type, label, half: nil)
    comment = "Демонстрационный календарь #{@year}: #{label}"
    return if employee.leave_requests.exists?(leave_type:, employee_comment: comment)
    if leave_type.code == "BIRTHDAY"
      return if employee.leave_requests.where(leave_type:, starts_on: @dates)
        .where("status IN (0, 1) OR birthday_used = TRUE").exists?
    elsif !half.nil?
      period = half.zero? ? (@dates.first..Date.new(@year, 6, 30)) : (Date.new(@year, 7, 1)..@dates.last)
      return if employee.leave_requests.where(leave_type:, status: %i[approved recalled interrupted])
        .where("starts_on <= ? AND COALESCE(recalled_on - 1, returned_on - 1, ends_on) >= ?", period.last, period.first).exists?
    end

    starts_on, ends_on = yield
    request = employee.leave_requests.create!(leave_type:, starts_on:, ends_on:,
      employee_comment: comment)
    request.approve!(by: employee.manager, comment: "Демонстрационные данные", legal_review: {
      conditions_confirmed: true, working_year_starts_on: @dates.first,
      working_year_ends_on: @dates.last, entitlement_days: employee.annual_default_days(on: @dates.first)
    })
  end

  def available_period(employee, preferred_start)
    occupied = employee.leave_requests.where(status: %i[pending approved recalled interrupted])
      .where("starts_on <= ? AND ends_on >= ?", @dates.last, @dates.first)
      .map { |request| request.starts_on..request.effective_ends_on }
    starts_on = (@dates.first..(@dates.last - 6)).sort_by { |date| (date - preferred_start).abs }.find do |date|
      occupied.none? { |period| date <= period.last && date + 6 >= period.first }
    end
    raise "В демонстрационном году нет свободного недельного периода" unless starts_on

    [ starts_on, starts_on + 6 ]
  end
end
