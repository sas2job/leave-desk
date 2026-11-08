require "date"

module DemoBirthdayDates
  MONTH_DAYS = begin
    random = Random.new(20_261_108)
    Array.new(20) do
      date = Date.ordinal(2001, random.rand(1..365))
      [ date.month, date.day ].freeze
    end.freeze
  end

  def self.for_index(index, year: 1990)
    month, day = MONTH_DAYS.fetch(index)
    Date.new(year, month, day)
  end
end
