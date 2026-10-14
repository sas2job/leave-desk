module Manager
  class CalendarsController < ApplicationController
    before_action :require_calendar_access

    def show
      require_string_fields!(params, :year, :month)
      @year = parse_decimal_filter(params.fetch(:year, Date.current.year)) || Date.current.year
      @year = Date.current.year unless @year.between?(2000, 2100)
      if params[:month] == "all"
        @month = nil
        @dates = (Date.new(@year, 1, 1)..Date.new(@year, 12, 31)).to_a
      else
        @month = parse_decimal_filter(params.fetch(:month, Date.current.month))
        @month = Date.current.month unless @month&.between?(1, 12)
        @dates = Date.new(@year, @month, 1).all_month.to_a
      end

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
        first_visible_date = [ request.starts_on, @dates.first ].max
        last_visible_date = [ request.ends_on, @dates.last ].min
        (first_visible_date..last_visible_date).each { |date| days << date }
      end
      { employee:, leave_days:, birthday: birthday_in_year(employee) }
    end

    def birthday_in_year(employee)
      birthday = employee.birthday_on
      birthday && Date.new(@year, birthday.month, birthday.day)
    rescue Date::Error
      nil
    end
  end
end
