module Manager
  class CalendarsController < ApplicationController
    TYPE_TONES = { "ANNUAL" => 0, "SICK" => 1, "UNPAID" => 2, "BIRTHDAY" => 3 }.freeze

    before_action :require_calendar_access

    def show
      require_string_fields!(params, :year, :month)
      @window = CalendarWindow.new(year: params[:year], month: params[:month])
      @year, @month, @dates = @window.year, @window.month, @window.dates

      @calendar_off_days = FederalCalendar.nonworking_dates(@dates)

      employees = calendar_employees.order(:name).to_a
      requests_by_employee = LeaveRequest.where(employee_id: employees.map(&:id), status: :approved)
        .includes(:leave_type)
        .where("starts_on <= ? AND ends_on >= ?", @dates.last, @dates.first)
        .group_by(&:employee_id)
      @rows = employees.map { |employee| calendar_row(employee, requests_by_employee.fetch(employee.id, [])) }
      @leave_types = @rows.flat_map { |row| row[:requests].map(&:leave_type) }.uniq.sort_by(&:name)
      @type_colors = type_colors_for(@leave_types)
      @coverage = @dates.index_with { 0 }
      @rows.each { |row| row[:leave_days].each { |date| @coverage[date] += 1 } }
      @focus_date = @coverage.find { |_, count| count >= 2 }&.first ||
        @coverage.find { |_, count| count.positive? }&.first
    end

    private

    def require_calendar_access
      head :forbidden unless Current.user.manager? || Current.user.administrator?
    end

    def calendar_employees
      return Current.user.direct_reports.where(active: true) if Current.user.manager?

      User.where(role: %i[employee manager], active: true)
    end

    def calendar_row(employee, requests)
      leave_days = requests.each_with_object(Set.new) do |request, days|
        next unless (visible_dates = @window.visible_dates_for(request))

        visible_dates.each { |date| days << date }
      end
      { employee:, requests: requests.sort_by(&:period_start_minute), leave_days:,
        birthday: birthday_in_year(employee) }
    end

    def type_colors_for(leave_types)
      colors = {}
      used = Set.new
      leave_types.each do |leave_type|
        tone = TYPE_TONES[leave_type.code.split("_").last]
        next unless tone && used.add?(tone)

        colors[leave_type.id] = tone
      end
      leave_types.each do |leave_type|
        next if colors.key?(leave_type.id)

        tone = (0..4).find { |index| !used.include?(index) } || colors.size % 5
        colors[leave_type.id] = tone
        used.add(tone)
      end
      colors
    end

    def birthday_in_year(employee)
      employee.birthday_in_year(@year)
    end
  end
end
