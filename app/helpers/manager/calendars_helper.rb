module Manager::CalendarsHelper
  DAY_WIDTH = 40
  YEAR_DAY_WIDTH = 3

  def timeline_bar_style(request, dates, day_width: DAY_WIDTH)
    minutes_per_day = LeaveRequest::MINUTES_PER_DAY
    first_minute = dates.first.jd * minutes_per_day
    last_minute = (dates.last.jd + 1) * minutes_per_day
    start_minute = [ request.period_start_minute, first_minute ].max
    end_minute = [ request.period_end_minute, last_minute ].min
    first_day = start_minute.div(minutes_per_day)
    last_day = (end_minute - 1).div(minutes_per_day)
    column = first_day - dates.first.jd + 1
    span = last_day - first_day + 1
    left = start_minute % minutes_per_day * day_width / minutes_per_day.to_f
    right = (minutes_per_day - end_minute % minutes_per_day) % minutes_per_day * day_width / minutes_per_day.to_f

    "grid-column: #{column} / span #{span}; margin-left: #{left.round(2)}px; margin-right: #{right.round(2)}px"
  end

  def timeline_date_anchor(date)
    prefix = @month ? "team-date" : "team-year-date"
    "#{prefix}-#{date.iso8601}"
  end

  def timeline_overlap_options
    @report.months.flat_map do |month|
      month[:ranges].map do |range|
        label = "#{format_date(range[:starts_on])}–#{format_date(range[:ends_on])} · #{range[:employees].size} чел."
        [ label, range[:starts_on].iso8601 ]
      end
    end
  end

  def timeline_bar_label(request)
    period = "#{format_date(request.starts_on)} — #{format_date(request.effective_ends_on)}"
    period += ", #{request.start_time_label}–#{request.end_time_label}" if request.precise_time?
    "#{team_leave_type_name(request)}: #{period}. Согласовано"
  end
end
