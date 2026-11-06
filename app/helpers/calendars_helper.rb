module CalendarsHelper
  def personal_year_day_description(date, requests)
    labels = [ format_date(date) ]
    labels << "Нерабочий день" if @calendar_off_days.include?(date)
    labels << "День рождения" if @birthday == date
    requests.each do |request|
      status = request.pending? ? "На рассмотрении" : "Согласовано"
      labels << "#{request.leave_type.name}, #{status}, #{request.start_time_label}–#{request.end_time_label}"
    end
    labels.join(" — ")
  end
end
