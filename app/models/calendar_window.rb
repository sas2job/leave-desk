class CalendarWindow
  FIRST_YEAR = 2025
  LAST_YEAR = 2050
  YEARS = FIRST_YEAR..LAST_YEAR

  attr_reader :year, :month, :dates

  def initialize(year:, month:, today: Date.current)
    @year = parse_decimal(year) || today.year
    @year = today.year.clamp(FIRST_YEAR, LAST_YEAR) unless YEARS.cover?(@year)

    if month == "all"
      @month = nil
      @dates = (Date.new(@year, 1, 1)..Date.new(@year, 12, 31)).to_a
    else
      @month = parse_decimal(month)
      @month = today.month unless @month&.between?(1, 12)
      @dates = Date.new(@year, @month, 1).all_month.to_a
    end
  end

  def visible_dates_for(request)
    first = [ request.starts_on, dates.first ].max
    last = [ request.ends_on, dates.last ].min
    first..last if first <= last
  end

  private

  def parse_decimal(value)
    text = value.to_s
    Integer(text, 10, exception: false) if /\A[0-9]+\z/.match?(text)
  end
end
