module Manager::CalendarsHelper
  DAY_WIDTH = 40

  def timeline_bar_style(request, dates)
    minutes_per_day = LeaveRequest::MINUTES_PER_DAY
    first_minute = dates.first.jd * minutes_per_day
    last_minute = (dates.last.jd + 1) * minutes_per_day
    start_minute = [ request.period_start_minute, first_minute ].max
    end_minute = [ request.period_end_minute, last_minute ].min
    first_day = start_minute.div(minutes_per_day)
    last_day = (end_minute - 1).div(minutes_per_day)
    column = first_day - dates.first.jd + 1
    span = last_day - first_day + 1
    left = start_minute % minutes_per_day * DAY_WIDTH / minutes_per_day.to_f
    right = (minutes_per_day - end_minute % minutes_per_day) % minutes_per_day * DAY_WIDTH / minutes_per_day.to_f

    "grid-column: #{column} / span #{span}; margin-left: #{left.round(2)}px; margin-right: #{right.round(2)}px"
  end

  def timeline_bar_label(request)
    period = "#{format_date(request.starts_on)} — #{format_date(request.ends_on)}"
    period += ", #{request.start_time_label}–#{request.end_time_label}" if request.precise_time?
    "#{request.leave_type.name}: #{period}. Согласовано"
  end
end
