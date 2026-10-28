require "test_helper"
require "open3"

class ImportFederalCalendarTest < ActiveSupport::TestCase
  INVALID_DATES = [ "infinity", "-infinity", "2026-02-30", "2026-1-01" ].freeze

  test "CLI reports invalid raw holidays without a backtrace" do
    INVALID_DATES.each do |value|
      Tempfile.create([ "federal-calendar", ".json" ]) do |file|
        file.write({ year: 2026, legal_basis: "НПА", public_holidays: [ value ], transfers: [] }.to_json)
        file.flush

        stdout, stderr, status = Open3.capture3(
          { "RAILS_ENV" => "test" }, RbConfig.ruby,
          Rails.root.join("bin/import-federal-calendar").to_s, file.path
        )

        assert_empty stdout
        assert_equal 1, status.exitstatus
        assert_includes stderr,
          "Импорт не выполнен: Праздничные даты должны быть в формате ГГГГ-ММ-ДД"
        assert_no_match(/NoMethodError|Traceback/, stderr)
      end
    end
  end
end
