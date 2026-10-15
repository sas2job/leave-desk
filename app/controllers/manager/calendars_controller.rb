module Manager
  class CalendarsController < ApplicationController
    before_action :require_calendar_access

    def show
      require_string_fields!(params, :year, :month)
      @window = CalendarWindow.new(year: params[:year], month: params[:month])
      @year, @month, @dates = @window.year, @window.month, @window.dates

      @calendar_off_days = FederalCalendar.nonworking_dates(@dates)

      employees = calendar_employees.order(:name).to_a
      requests_by_employee = LeaveRequest.where(employee_id: employees.map(&:id), status: :approved)
        .where("starts_on <= ? AND ends_on >= ?", @dates.last, @dates.first)
        .group_by(&:employee_id)
      @rows = employees.map { |employee| calendar_row(employee, requests_by_employee.fetch(employee.id, [])) }
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
      { employee:, leave_days:, birthday: birthday_in_year(employee) }
    end

    def birthday_in_year(employee)
      employee.birthday_in_year(@year)
    end
  end
end
