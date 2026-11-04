require "test_helper"
require "open3"
require "tmpdir"
require "timeout"

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
        assert_equal 2, status.exitstatus
        assert_includes stderr,
          "Импорт не выполнен: Праздничные даты должны быть в формате ГГГГ-ММ-ДД"
        assert_no_match(/NoMethodError|Traceback/, stderr)
      end
    end
  end

  test "CLI rejects a FIFO without waiting for a writer" do
    Dir.mktmpdir("federal-calendar") do |directory|
      path = File.join(directory, "calendar.json")
      File.mkfifo(path)
      stdin, stdout, stderr, process = Open3.popen3(
        { "RAILS_ENV" => "test" }, RbConfig.ruby,
        Rails.root.join("bin/import-federal-calendar").to_s, path
      )

      begin
        status = Timeout.timeout(5) { process.value }
        assert_equal 2, status.exitstatus
        assert_empty stdout.read
        assert_includes stderr.read, "обычный файл JSON"
      ensure
        if process.alive?
          Process.kill("KILL", process.pid)
          process.join
        end
        stdin.close
        stdout.close
        stderr.close
      end
    end
  end

  test "CLI rejects duplicate replace flags before loading Rails" do
    stdout, stderr, status = Open3.capture3(
      { "RAILS_ENV" => "test" }, RbConfig.ruby,
      Rails.root.join("bin/import-federal-calendar").to_s,
      "--replace", "--replace", "./calendar.json"
    )

    assert_equal 2, status.exitstatus
    assert_empty stdout
    assert_includes stderr, "bin/import-federal-calendar --replace ./calendar.json"
  end
end
