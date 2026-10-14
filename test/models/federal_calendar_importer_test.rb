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

  private

  def calendar_json
    { year: 2026, legal_basis: "НПА", public_holidays: [ "2026-01-01" ],
      transfers: [ { from: "2026-03-07", to: "2026-03-09" } ] }.to_json
  end
end
