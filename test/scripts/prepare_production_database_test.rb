require "test_helper"
require "fileutils"
require "open3"
require "tmpdir"

class PrepareProductionDatabaseTest < ActiveSupport::TestCase
  test "seeds reference calendars before granting runtime access" do
    Dir.mktmpdir("leave-desk-prepare-database") do |directory|
      bin_directory = File.join(directory, "bin")
      FileUtils.mkdir_p(bin_directory)
      FileUtils.cp(Rails.root.join("bin/prepare-production-database"), bin_directory)
      calls = File.join(directory, "calls")
      write_stub(File.join(bin_directory, "rails"), 'printf "rails %s\n" "$*" >> "$CALLS"')
      write_stub(File.join(bin_directory, "psql"), 'printf "psql\n" >> "$CALLS"')

      _stdout, stderr, status = Open3.capture3({
        "RAILS_ENV" => "production",
        "LEAVE_DESK_BOOTSTRAP_DATABASE_PASSWORD" => "bootstrap-test",
        "LEAVE_DESK_RUNTIME_DATABASE_PASSWORD" => "runtime-test",
        "PATH" => "#{bin_directory}:#{ENV.fetch('PATH')}",
        "CALLS" => calls
      }, "bash", File.join(bin_directory, "prepare-production-database"), chdir: directory)

      assert status.success?, stderr
      assert_equal [ "rails db:prepare", "rails db:seed" ], File.readlines(calls, chomp: true).first(2)
      assert_equal 4, File.readlines(calls).count { |line| line.start_with?("psql") }
    end
  end

  private

  def write_stub(path, command)
    File.write(path, "#!/bin/sh\n#{command}\n")
    File.chmod(0o700, path)
  end
end
