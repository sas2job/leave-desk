require "test_helper"
require "digest"
require "fileutils"
require "open3"
require "tmpdir"

class BackupScriptTest < ActiveSupport::TestCase
  test "parallel runs in the same second publish separate verifiable backups" do
    with_backup_environment do |directory, environment|
      results = %w[first second].map do |payload|
        Thread.new { run_backup(environment.merge("DUMP_PAYLOAD" => payload)) }
      end.map(&:value)

      results.each do |output, error, status|
        assert status.success?, "#{output}\n#{error}"
      end
      archives = Dir.glob(File.join(directory, "leave-desk-*.dump"))
      assert_equal 2, archives.size
      assert_equal %w[first second], archives.map { |archive| File.binread(archive) }.sort
      archives.each { |archive| assert_verifiable_pair(archive, environment) }
    end
  end

  test "a failed run cannot remove or change a concurrent successful backup" do
    with_backup_environment do |directory, environment|
      successful = Thread.new do
        run_backup(environment.merge("DUMP_PAYLOAD" => "complete"))
      end
      failed = Thread.new do
        run_backup(environment.merge("DUMP_PAYLOAD" => "partial", "DUMP_FAIL" => "yes"))
      end
      _output, _error, success_status = successful.value
      _output, _error, failure_status = failed.value

      assert success_status.success?
      assert_not failure_status.success?
      archives = Dir.glob(File.join(directory, "leave-desk-*.dump"))
      assert_equal 1, archives.size
      assert_equal "complete", File.binread(archives.first)
      assert_verifiable_pair(archives.first, environment)
      assert_empty Dir.glob(File.join(directory, ".leave-desk-*"))
    end
  end

  test "a preexisting same-second archive is not overwritten" do
    with_backup_environment do |directory, environment|
      existing = File.join(directory, "leave-desk-20261015T000000Z.dump")
      File.binwrite(existing, "previous")

      _output, error, status = run_backup(environment.merge("DUMP_PAYLOAD" => "new"))

      assert status.success?, error
      assert_equal "previous", File.binread(existing)
      archives = Dir.glob(File.join(directory, "leave-desk-*.dump"))
      assert_equal 2, archives.size
      assert_equal "new", File.binread((archives - [ existing ]).sole)
    end
  end

  private

  def with_backup_environment
    Dir.mktmpdir("leave-desk-backup-test") do |directory|
      executable_directory = File.join(directory, "bin")
      FileUtils.mkdir_p(executable_directory)
      date = File.join(executable_directory, "date")
      File.write(date, "#!/bin/sh\nprintf '20261015T000000Z\\n'\n")
      dump = File.join(executable_directory, "pg_dump")
      File.write(dump, <<~'SH')
        #!/usr/bin/env bash
        set -euo pipefail
        for argument in "$@"; do
          case "$argument" in
            --file=*) archive="${argument#--file=}" ;;
          esac
        done
        printf '%s' "$DUMP_PAYLOAD" > "$archive"
        sleep 0.1
        [[ "${DUMP_FAIL:-}" != yes ]]
      SH
      restore = File.join(executable_directory, "pg_restore")
      File.write(restore, "#!/bin/sh\nexit 0\n")
      FileUtils.chmod(0o700, [ date, dump, restore ])
      environment = { "PATH" => "#{executable_directory}:#{ENV.fetch('PATH')}",
                      "DATABASE_URL" => "postgres://localhost/isolated",
                      "BACKUP_DIRECTORY" => directory }
      yield directory, environment
    end
  end

  def run_backup(environment)
    Open3.capture3(environment, Rails.root.join("bin/backup").to_s)
  end

  def assert_verifiable_pair(archive, environment)
    digest = Digest::SHA256.file(archive).hexdigest
    assert_equal "#{digest}  #{File.basename(archive)}\n", File.read("#{archive}.sha256")
    restore_environment = environment.merge("RESTORE_DATABASE_URL" => "postgres://localhost/isolated",
                                             "ALLOW_DATABASE_RESTORE" => "yes")
    _output, error, status = Open3.capture3(restore_environment,
                                            Rails.root.join("bin/restore").to_s, archive)
    assert status.success?, error
  end
end
