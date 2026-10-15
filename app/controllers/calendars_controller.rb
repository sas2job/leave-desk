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
        start_slot = request.starts_on.jd * 2 + (request.starts_afternoon? ? 1 : 0)
        end_slot = request.ends_on.jd * 2 + (request.ends_morning? ? 1 : 2)
        slots[:morning] = request if start_slot <= date.jd * 2 && end_slot > date.jd * 2
        slots[:afternoon] = request if start_slot <= date.jd * 2 + 1 && end_slot > date.jd * 2 + 1
      end
    end
    @birthday = birthday_in_year
  end

  private

  def birthday_in_year
    birthday = Current.user.birthday_on
    birthday && Date.new(@year, birthday.month, birthday.day)
  rescue Date::Error
    nil
  end
end
