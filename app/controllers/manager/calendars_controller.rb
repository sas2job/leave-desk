module Manager
  class CalendarsController < ApplicationController
    before_action :require_calendar_access

    def show
      @year = Integer(params.fetch(:year, Date.current.year), exception: false) || Date.current.year
      @year = Date.current.year unless @year.between?(2000, 2100)
      if params[:month] == "all"
        @month = nil
        @dates = (Date.new(@year, 1, 1)..Date.new(@year, 12, 31)).to_a
      else
        @month = Integer(params.fetch(:month, Date.current.month).to_s, 10, exception: false)
        @month = Date.current.month unless @month&.between?(1, 12)
        @dates = Date.new(@year, @month, 1).all_month.to_a
      end

      employees = calendar_employees.includes(leave_requests: :leave_type).order(:name)
      @rows = employees.map { |employee| calendar_row(employee) }
    end

    private

    def require_calendar_access
      head :forbidden unless Current.user.manager? || Current.user.administrator?
    end

    def calendar_employees
      return Current.user.direct_reports.where(active: true) if Current.user.manager?

      User.where(role: %i[employee manager], active: true)
    end

    def calendar_row(employee)
      approved = employee.leave_requests.select(&:approved?)
      leave_days = approved.each_with_object(Set.new) do |request, days|
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
