class PublicHoliday
  def self.dates_for_year(year, region_id: nil)
    dates = FederalCalendar.find_by(year:)&.public_holidays || RussianFederalHoliday.fixed_dates_for(year)
    if region_id
      dates += RegionalCalendar.find_by(year:, region_id:)&.public_holidays || []
    end
    dates.to_set
  end

  def self.on?(date, region_id: nil)
    dates_for_year(date.year, region_id:).include?(date)
  end

  def self.count_between(starts_on, ends_on, region_id: nil)
    (starts_on.year..ends_on.year).sum do |year|
      dates_for_year(year, region_id:).count { |date| date >= starts_on && date <= ends_on }
    end
  end
end
