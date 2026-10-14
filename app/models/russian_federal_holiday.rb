class RussianFederalHoliday
  FIXED_DATES = [
    [ 1, 1 ], [ 1, 2 ], [ 1, 3 ], [ 1, 4 ], [ 1, 5 ], [ 1, 6 ], [ 1, 7 ], [ 1, 8 ],
    [ 2, 23 ], [ 3, 8 ], [ 5, 1 ], [ 5, 9 ], [ 6, 12 ], [ 11, 4 ]
  ].freeze

  def self.on?(date)
    calendar = FederalCalendar.find_by(year: date.year)
    calendar ? calendar.public_holiday?(date) : FIXED_DATES.include?([ date.month, date.day ])
  end

  def self.count_between(starts_on, ends_on)
    calendars = FederalCalendar.where(year: starts_on.year..ends_on.year).index_by(&:year)
    (starts_on.year..ends_on.year).sum do |year|
      dates = calendars[year]&.public_holidays || fixed_dates_for(year)
      dates.count { |date| date >= starts_on && date <= ends_on }
    end
  end

  def self.fixed_dates_for(year)
    FIXED_DATES.map { |month, day| Date.new(year, month, day) }
  end
end
