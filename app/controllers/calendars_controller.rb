class CalendarsController < ApplicationController
  def show
    require_string_fields!(params, :year, :month)
    @year = Integer(params.fetch(:year, Date.current.year).to_s, 10, exception: false) || Date.current.year
    @year = Date.current.year unless @year.between?(2000, 2100)

    if params[:month] == "all"
      @month = nil
      @dates = (Date.new(@year, 1, 1)..Date.new(@year, 12, 31)).to_a
    else
      @month = Integer(params.fetch(:month, Date.current.month).to_s, 10, exception: false)
      @month = Date.current.month unless @month&.between?(1, 12)
      @dates = Date.new(@year, @month, 1).all_month.to_a
    end

    @leave_requests = Current.user.leave_requests.includes(:leave_type)
      .where(status: %i[pending approved])
      .where("starts_on <= ? AND ends_on >= ?", @dates.last, @dates.first)
      .order(:starts_on)
    @leave_requests_by_date = @leave_requests.each_with_object({}) do |request, requests_by_date|
      first_visible_date = [ request.starts_on, @dates.first ].max
      last_visible_date = [ request.ends_on, @dates.last ].min
      (first_visible_date..last_visible_date).each do |date|
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
