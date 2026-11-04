class RegionalHolidayNotifier
  MORNING_HOURS = 9...12

  def self.deliver_due!(at: Time.current)
    users = User.where(active: true).where.not(region_id: nil).select(:id, :region_id, :time_zone)
    calendars = {}
    users.find_each do |user|
      local_time = at.in_time_zone(user.time_zone)
      next unless MORNING_HOURS.cover?(local_time.hour)

      holiday_on = local_time.to_date + 1
      key = [ user.region_id, holiday_on.year ]
      calendar = calendars.fetch(key) do
        calendars[key] = RegionalCalendar.find_by(region_id: user.region_id, year: holiday_on.year)
      end
      next unless calendar&.day_off?(holiday_on)

      Notification.create_or_find_by!(recipient_id: user.id, region_id: user.region_id, holiday_on:)
    end
  end
end
