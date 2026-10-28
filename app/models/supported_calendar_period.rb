module SupportedCalendarPeriod
  FIRST_DATE = Date.new(2000, 1, 1)
  LAST_DATE = Date.new(2100, 12, 31)
  DATES = FIRST_DATE..LAST_DATE
  YEARS = FIRST_DATE.year..LAST_DATE.year

  def self.date_error
    "должна быть между #{FIRST_DATE.strftime('%d.%m.%Y')} и #{LAST_DATE.strftime('%d.%m.%Y')}"
  end
end
