module Manager
  class CalendarsController < ApplicationController
    before_action :require_manager

    def show
      @year = Integer(params.fetch(:year, Date.current.year), exception: false) || Date.current.year
      @year = Date.current.year unless @year.between?(2000, 2100)
      @dates = (Date.new(@year, 1, 1)..Date.new(@year, 12, 31)).to_a
      employees = Current.user.direct_reports.where(active: true)
        .includes(leave_requests: :leave_type).order(:name)
      @rows = employees.map { |employee| calendar_row(employee) }
    end

    private

    def require_manager
      head :forbidden unless Current.user.manager?
    end

    def calendar_row(employee)
      approved = employee.leave_requests.select(&:approved?)
      leave_days = approved.each_with_object(Set.new) do |request, days|
        ((request.starts_on..request.ends_on).to_a & @dates).each { |date| days << date }
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
