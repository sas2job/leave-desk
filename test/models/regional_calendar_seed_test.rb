require "test_helper"

class RegionalCalendarSeedTest < ActiveSupport::TestCase
  test "verified 2026 dates and provisional 2027 dates are seeded without overwriting edits" do
    load Rails.root.join("db/seeds/regional_calendars.rb")
    region = Region.find_by!(code: "RU-TA")
    assert_equal 28, Region.count
    calendar_2026 = RegionalCalendar.find_by!(region:, year: 2026)
    calendar_2027 = RegionalCalendar.find_by!(region:, year: 2027)

    assert_predicate calendar_2026, :complete?
    assert_equal %w[2026-03-20 2026-05-27 2026-08-30 2026-11-06],
      calendar_2026.public_holidays.map(&:iso8601)
    assert_not calendar_2027.complete?
    assert_equal %w[2027-08-30 2027-11-06], calendar_2027.public_holidays.map(&:iso8601)
    bashkortostan = Region.find_by!(code: "RU-BA")
    assert_equal %w[2026-03-20 2026-05-27],
      RegionalCalendar.find_by!(region: bashkortostan, year: 2026).public_holidays.map(&:iso8601)
    assert_not RegionalCalendar.find_by!(region: bashkortostan, year: 2027).complete?

    krasnodar = Region.find_by!(code: "RU-KDA")
    { 2026 => "2026-04-21", 2027 => "2027-05-11" }.each do |year, date|
      calendar = RegionalCalendar.find_by!(region: krasnodar, year:)
      assert_not calendar.complete?
      assert_equal [ date ], calendar.public_holidays.map(&:iso8601)
    end

    calendar_2026.update!(legal_basis: "Проверено администратором")
    assert_no_difference("Region.count") do
      assert_no_difference("RegionalCalendar.count") do
        load Rails.root.join("db/seeds/regional_calendars.rb")
      end
    end
    assert_equal "Проверено администратором", calendar_2026.reload.legal_basis
  end
end
