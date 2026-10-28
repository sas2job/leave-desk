require "test_helper"

class CalendarWindowTest < ActiveSupport::TestCase
  RequestPeriod = Struct.new(:starts_on, :ends_on)
  TODAY = Date.new(2026, 10, 14)

  test "month window handles a leap day and clips overlapping requests" do
    window = CalendarWindow.new(year: "2028", month: "02", today: TODAY)

    assert_equal Date.new(2028, 2, 1), window.dates.first
    assert_equal Date.new(2028, 2, 29), window.dates.last
    assert_equal 29, window.dates.size
    assert_equal window.dates.first..window.dates.last,
      window.visible_dates_for(RequestPeriod.new(Date.new(2028, 1, 15), Date.new(2028, 3, 10)))
    assert_nil window.visible_dates_for(RequestPeriod.new(Date.new(2028, 1, 1), Date.new(2028, 1, 31)))
    assert_nil window.visible_dates_for(RequestPeriod.new(Date.new(2028, 3, 1), Date.new(2028, 3, 31)))
  end

  test "year window starts in 2025 and keeps the upper boundary" do
    first = CalendarWindow.new(year: "2025", month: "all", today: TODAY)
    last = CalendarWindow.new(year: "2050", month: "all", today: TODAY)

    assert_nil first.month
    assert_equal Date.new(2025, 1, 1), first.dates.first
    assert_equal Date.new(2025, 12, 31), first.dates.last
    assert_equal 365, first.dates.size
    assert_equal Date.new(2050, 1, 1), last.dates.first
    assert_equal Date.new(2050, 12, 31), last.dates.last
    assert_equal 365, last.dates.size
  end

  test "invalid filters fall back to current year and month" do
    [ nil, "1976", "2000", "2024", "2051", "2100", "0x7ea", "2_026" ].each do |year|
      window = CalendarWindow.new(year:, month: "13", today: TODAY)

      assert_equal 2026, window.year
      assert_equal 10, window.month
      assert_equal Date.new(2026, 10, 1), window.dates.first
    end
  end

  test "default year stays within supported range after 2050" do
    window = CalendarWindow.new(year: nil, month: 6, today: Date.new(2051, 6, 1))

    assert_equal 2050, window.year
    assert_equal Date.new(2050, 6, 1), window.dates.first
  end
end
