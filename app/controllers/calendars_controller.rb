class CalendarsController < ApplicationController
  def show
    require_string_fields!(params, :year, :month)
    window = CalendarWindow.new(year: params[:year], month: params[:month])
    @year, @month, @dates = window.year, window.month, window.dates

    @calendar_off_days = FederalCalendar.nonworking_dates(@dates)

    @leave_requests = Current.user.leave_requests.includes(:leave_type)
      .where(status: %i[pending approved])
      .where("starts_on <= ? AND ends_on >= ?", @dates.last, @dates.first)
      .order(:starts_on)
    @leave_requests_by_date = @leave_requests.each_with_object({}) do |request, requests_by_date|
      next unless (visible_dates = window.visible_dates_for(request))

      visible_dates.each do |date|
        slots = (requests_by_date[date] ||= {})
        day_start = date.jd * LeaveRequest::MINUTES_PER_DAY
        if request.period_start_minute < day_start + LeaveRequest::HALF_DAY_MINUTES &&
            request.period_end_minute > day_start
          (slots[:morning] ||= []) << request
        end
        if request.period_start_minute < day_start + LeaveRequest::MINUTES_PER_DAY &&
            request.period_end_minute > day_start + LeaveRequest::HALF_DAY_MINUTES
          (slots[:afternoon] ||= []) << request
        end
      end
    end
    @birthday = birthday_in_year
  end

  private

  def birthday_in_year
    Current.user.birthday_in_year(@year)
  end
end
