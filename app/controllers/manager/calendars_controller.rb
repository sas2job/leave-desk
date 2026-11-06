module Manager
  class CalendarsController < ApplicationController
    TYPE_TONES = { "ANNUAL" => 0, "SICK" => 1, "UNPAID" => 2, "BIRTHDAY" => 3 }.freeze

    before_action :require_calendar_access
    before_action :require_overlap_access, only: :overlaps
    before_action :load_calendar

    def show
      return if params[:overlap_on].blank?
      return head :forbidden unless Current.user.manager?

      date = FederalCalendar.parse_iso_date(params[:overlap_on])
      @selected_range = @report.months.flat_map { |month| month[:ranges] }.find do |range|
        date && (range[:starts_on]..range[:ends_on]).cover?(date)
      end
      raise ActionController::BadRequest, "Неизвестный период пересечения" unless @selected_range

      selected_ids = @selected_range[:employees].map(&:id).to_set
      @rows.select! { |row| selected_ids.include?(row[:employee].id) }
      @coverage = coverage_for(@rows)
      @focus_date = date
    end

    def overlaps
      respond_to do |format|
        format.html
        format.md do
          send_data @report.to_markdown, filename: "leave-overlaps-#{@year}#{@month ? '-%02d' % @month : ''}.md",
            type: "text/markdown; charset=utf-8", disposition: "attachment"
        end
      end
    end

    private

    def require_overlap_access
      head :forbidden unless Current.user.manager?
    end

    def load_calendar
      require_string_fields!(params, :year, :month, :overlap_on)
      @window = CalendarWindow.new(year: params[:year], month: params[:month])
      @year, @month, @dates = @window.year, @window.month, @window.dates

      @calendar_off_days = FederalCalendar.nonworking_dates(@dates)

      employees = calendar_employees.order(:name).to_a
      @off_days_by_region = employees.map(&:region_id).uniq.index_with do |region_id|
        FederalCalendar.nonworking_dates(@dates, region_id:)
      end
      requests_by_employee = LeaveRequest.where(employee_id: employees.map(&:id), status: %i[approved recalled interrupted])
        .includes(:leave_type)
        .where("starts_on <= ? AND COALESCE(recalled_on - 1, returned_on - 1, ends_on) >= ?", @dates.last, @dates.first)
        .group_by(&:employee_id)
      @rows = employees.map { |employee| calendar_row(employee, requests_by_employee.fetch(employee.id, [])) }
      @leave_types = @rows.flat_map { |row| row[:requests].map(&:leave_type) }.uniq.sort_by(&:name)
      @type_colors = type_colors_for(@leave_types)
      @has_family_leave = @leave_types.any?(&:family_leave?)
      @leave_types.reject!(&:family_leave?)
      @coverage = coverage_for(@rows)
      @report = TeamCalendarOverlapReport.new(rows: @rows, coverage: @coverage, dates: @dates) if Current.user.manager?
      @focus_date = @coverage.find { |_, count| count >= 2 }&.first ||
        @coverage.find { |_, count| count.positive? }&.first
    end

    def coverage_for(rows)
      coverage = @dates.index_with { 0 }
      rows.each { |row| row[:leave_days].each { |date| coverage[date] += 1 } }
      coverage
    end

    def require_calendar_access
      head :forbidden unless Current.user.manager? || Current.user.administrator?
    end

    def calendar_employees
      return Current.user.direct_reports.where(active: true) if Current.user.manager?

      User.where(role: %i[employee manager], active: true)
    end

    def calendar_row(employee, requests)
      leave_days = requests.each_with_object(Set.new) do |request, days|
        next unless (visible_dates = @window.visible_dates_for(request, ends_on: request.effective_ends_on))

        visible_dates.each { |date| days << date }
      end
      { employee:, requests: requests.sort_by(&:period_start_minute), leave_days:,
        birthday: birthday_in_year(employee), off_days: @off_days_by_region.fetch(employee.region_id) }
    end

    def type_colors_for(leave_types)
      colors = {}
      used = Set.new
      leave_types.each do |leave_type|
        if leave_type.family_leave?
          colors[leave_type.id] = 4
          used.add(4)
          next
        end
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
