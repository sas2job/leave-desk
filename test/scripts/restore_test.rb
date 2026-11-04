require "test_helper"
require "digest"
require "fileutils"
require "open3"
require "tmpdir"

class RestoreScriptTest < ActiveSupport::TestCase
  test "restores an archive only after checking its matching sidecar" do
    with_restore_environment do |directory, environment, calls|
      archive = create_archive(directory, "leave-desk.dump", "valid archive")

      output, error, status = run_restore(environment.merge("DATABASE_URL" => "postgres://localhost/forbidden",
        "RESTORE_DATABASE_URL" => "postgresql:///isolated"), archive)

      assert status.success?, "#{output}\n#{error}"
      arguments = File.readlines(calls, chomp: true)
      assert_equal archive, arguments.last
      assert_equal "--", arguments[-2]
      assert_equal [ "--dbname=postgresql:///isolated" ], arguments.grep(/\A--dbname=/)
      %w[--exit-on-error --single-transaction --no-owner --no-privileges].each do |option|
        assert_includes arguments, option
      end
      assert_equal 7, arguments.length
    end
  end

  test "treats a leading dash archive name as a file" do
    with_restore_environment do |directory, environment, calls|
      create_archive(directory, "--clean", "valid archive")

      output, error, status = Open3.capture3(environment, Rails.root.join("bin/restore").to_s,
        "--clean", chdir: directory)

      assert status.success?, "#{output}\n#{error}"
      assert_equal [ "--", "--clean" ], File.readlines(calls, chomp: true).last(2)
    end
  end

  test "requires an explicit isolated database and restore confirmation before pg_restore" do
    with_restore_environment do |directory, environment, calls|
      archive = create_archive(directory, "leave-desk.dump", "valid archive")
      [ { "RESTORE_DATABASE_URL" => nil }, { "ALLOW_DATABASE_RESTORE" => nil },
        { "ALLOW_DATABASE_RESTORE" => "no" } ].each do |invalid_settings|
        _output, _error, status = run_restore(environment.merge(invalid_settings), archive)

        assert_not status.success?, invalid_settings.keys.first
        assert_not File.exist?(calls)
      end
    end
  end

  test "rejects a malformed restore database URL before pg_restore" do
    with_restore_environment do |directory, environment, calls|
      archive = create_archive(directory, "leave-desk.dump", "valid archive")

      [ "--help", "postgres://localhost/", "postgres://localhost/isolated private-canary" ].each do |url|
        _output, error, status = run_restore(environment.merge("RESTORE_DATABASE_URL" => url), archive)

        assert_equal 2, status.exitstatus
        assert_includes error, "RESTORE_DATABASE_URL must"
        assert_not_includes error, "private-canary"
        assert_not File.exist?(calls)
      end
    end
  end

  test "rejects a damaged selected archive before pg_restore" do
    with_restore_environment do |directory, environment, calls|
      archive = create_archive(directory, "leave-desk.dump", "valid archive")
      File.binwrite(archive, "damaged archive")

      _output, _error, status = run_restore(environment, archive)

      assert_not status.success?
      assert_not File.exist?(calls)
    end
  end

  test "rejects an extra argument before pg_restore" do
    with_restore_environment do |directory, environment, calls|
      archive = create_archive(directory, "leave-desk.dump", "valid archive")
      _output, error, status = run_restore(environment, archive, "unexpected")

      assert_equal 2, status.exitstatus
      assert_includes error, "PATH_TO_DUMP"
      assert_not File.exist?(calls)
    end
  end

  test "rejects a renamed pair while the original archive still exists" do
    with_restore_environment do |directory, environment, calls|
      original = create_archive(directory, "leave-desk.dump", "valid archive")
      renamed = File.join(directory, "renamed.dump")
      FileUtils.cp(original, renamed)
      FileUtils.cp("#{original}.sha256", "#{renamed}.sha256")

      _output, _error, status = run_restore(environment, renamed)

      assert_not status.success?
      assert_not File.exist?(calls)
    end
  end

  test "rejects a sidecar with more than one entry" do
    with_restore_environment do |directory, environment, calls|
      archive = create_archive(directory, "leave-desk.dump", "valid archive")
      File.open("#{archive}.sha256", "a") { |file| file.puts "#{'0' * 64}  other.dump" }

      _output, _error, status = run_restore(environment, archive)

      assert_not status.success?
      assert_not File.exist?(calls)
    end
  end

  test "rejects an oversized checksum sidecar before reading it" do
    with_restore_environment do |directory, environment, calls|
      archive = create_archive(directory, "leave-desk.dump", "valid archive")
      File.binwrite("#{archive}.sha256", "x" * 1_024)

      _output, error, status = run_restore(environment, archive)

      assert_equal 2, status.exitstatus
      assert_includes error, "Checksum file exceeds 512 bytes"
      assert_not File.exist?(calls)
    end
  end

  test "a missing checksum command is reported before restoring" do
    with_restore_environment do |directory, environment, calls|
      archive = create_archive(directory, "leave-desk.dump", "valid archive")
      isolated_bin = File.join(directory, "isolated-bin")
      Dir.mkdir(isolated_bin)
      %w[bash dirname basename].each do |name|
        executable = ENV.fetch("PATH").split(File::PATH_SEPARATOR).map { |path| File.join(path, name) }
                        .find { |path| File.executable?(path) }
        File.symlink(executable, File.join(isolated_bin, name))
      end
      File.symlink(File.join(directory, "bin", "pg_restore"), File.join(isolated_bin, "pg_restore"))

      _output, error, status = run_restore(environment.merge("PATH" => isolated_bin), archive)

      assert_not status.success?
      assert_includes error, "requires sha256sum in PATH"
      assert_not File.exist?(calls)
    end
  end

  test "an unavailable Bash capability is reported before restoring" do
    with_restore_environment do |directory, environment, calls|
      archive = create_archive(directory, "leave-desk.dump", "valid archive")
      script = Rails.root.join("bin/restore").to_s

      _output, error, status = Open3.capture3(environment, "bash", "-c",
                                              'enable -n mapfile; source "$1" "$2"', "bash", script, archive)

      assert_not status.success?
      assert_includes error, "requires Bash 4 or newer"
      assert_not File.exist?(calls)
    end
  end

  private

  def with_restore_environment
    Dir.mktmpdir("leave-desk-restore-test") do |directory|
      executable_directory = File.join(directory, "bin")
      FileUtils.mkdir_p(executable_directory)
      restore = File.join(executable_directory, "pg_restore")
      File.write(restore, "#!/bin/sh\nprintf '%s\\n' \"$@\" >> \"$RESTORE_CALLS\"\n")
      FileUtils.chmod(0o700, restore)
      calls = File.join(directory, "restore-calls")
      environment = { "PATH" => "#{executable_directory}:#{ENV.fetch('PATH')}",
                      "RESTORE_CALLS" => calls,
                      "RESTORE_DATABASE_URL" => "postgres://localhost/isolated",
                      "ALLOW_DATABASE_RESTORE" => "yes" }
      yield directory, environment, calls
    end
  end

  def create_archive(directory, name, contents)
    archive = File.join(directory, name)
    File.binwrite(archive, contents)
    File.write("#{archive}.sha256", "#{Digest::SHA256.hexdigest(contents)}  #{name}\n")
    archive
  end

  def run_restore(environment, archive, *extra_arguments)
    Open3.capture3(environment, Rails.root.join("bin/restore").to_s, archive, *extra_arguments)
  end
end
