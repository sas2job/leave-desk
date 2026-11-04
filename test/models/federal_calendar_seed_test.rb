require "test_helper"

class FederalCalendarSeedTest < ActiveSupport::TestCase
  test "seeds 2026 and 2027 transfers without replacing administrator edits" do
    load Rails.root.join("db/seeds/federal_calendars.rb")
    calendar_2026 = FederalCalendar.find_by!(year: 2026)
    calendar_2027 = FederalCalendar.find_by!(year: 2027)

    assert_equal RussianFederalHoliday.fixed_dates_for(2026), calendar_2026.public_holidays
    assert_equal [ { "from" => "2026-01-03", "to" => "2026-01-09" },
      { "from" => "2026-01-04", "to" => "2026-12-31" } ], calendar_2026.transfers
    assert_equal 3, calendar_2027.transfers.size

    calendar_2026.update!(legal_basis: "Проверено администратором")
    assert_no_difference("FederalCalendar.count") do
      load Rails.root.join("db/seeds/federal_calendars.rb")
    end
    assert_equal "Проверено администратором", calendar_2026.reload.legal_basis
  end
end
