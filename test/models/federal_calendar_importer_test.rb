require "test_helper"
require "stringio"

class FederalCalendarImporterTest < ActiveSupport::TestCase
  test "imports a calendar from JSON and requires explicit replacement" do
    calendar = FederalCalendarImporter.call(StringIO.new(calendar_json))
    assert_equal 2026, calendar.year
    assert_equal [ Date.new(2026, 1, 1) ], calendar.public_holidays
    assert_equal [ { "from" => "2026-03-07", "to" => "2026-03-09" } ], calendar.transfers

    error = assert_raises(FederalCalendarImporter::InvalidFile) do
      FederalCalendarImporter.call(StringIO.new(calendar_json))
    end
    assert_match(/уже существует/, error.message)

    replaced = FederalCalendarImporter.call(StringIO.new(calendar_json.sub("НПА", "Новый НПА")), replace: true)
    assert_equal calendar.id, replaced.id
    assert_equal "Новый НПА", replaced.legal_basis
  end

  test "invalid or oversized file cannot change a calendar" do
    calendar = FederalCalendarImporter.call(StringIO.new(calendar_json))
    [ "{bad", calendar_json.sub("2026-01-01", "2027-01-01"), "x" * (FederalCalendarImporter::MAX_BYTES + 1) ].each do |content|
      assert_raises(FederalCalendarImporter::InvalidFile) do
        FederalCalendarImporter.call(StringIO.new(content), replace: true)
      end
    end
    assert_equal [ Date.new(2026, 1, 1) ], calendar.reload.public_holidays
    assert_equal "НПА", calendar.legal_basis
  end

  test "rejects oversized JSON collections before date normalization" do
    data = JSON.parse(calendar_json)
    data["public_holidays"] = [ "2026-01-01" ] * 367
    data["transfers"] = [ { "from" => "2026-03-07", "to" => "2026-03-09" } ] * 367

    error = assert_raises(FederalCalendarImporter::InvalidFile) do
      FederalCalendarImporter.call(StringIO.new(JSON.generate(data)))
    end
    assert_match(/Слишком много/, error.message)
    assert_not FederalCalendar.exists?(year: 2026)
  end

  test "bundled federal calendars import and apply decree and automatic transfers" do
    expected_dates = {
      2025 => { workdays: %w[2025-11-01], days_off: %w[2025-05-02 2025-11-03 2025-12-31] },
      2026 => { workdays: [], days_off: %w[2026-01-09 2026-03-09 2026-05-11 2026-12-31] },
      2027 => { workdays: %w[2027-02-20], days_off: %w[2027-02-22 2027-05-03 2027-05-10 2027-06-14 2027-11-05 2027-12-31] }
    }

    expected_dates.each do |year, dates|
      calendar = File.open(Rails.root.join("data/federal-calendar-#{year}.json")) do |file|
        FederalCalendarImporter.call(file)
      end

      assert_equal year, calendar.year
      assert_equal 14, calendar.public_holidays.size
      assert_equal 247, (Date.new(year, 1, 1)..Date.new(year, 12, 31)).count { |date| !calendar.day_off?(date) }
      dates.fetch(:workdays).each { |day| assert_not calendar.day_off?(Date.iso8601(day)), day }
      dates.fetch(:days_off).each { |day| assert calendar.day_off?(Date.iso8601(day)), day }
    end
  end

  private

  def calendar_json
    { year: 2026, legal_basis: "НПА", public_holidays: [ "2026-01-01" ],
      transfers: [ { from: "2026-03-07", to: "2026-03-09" } ] }.to_json
  end
end
