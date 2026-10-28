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

  test "an existing shared directory is rejected without changing it" do
    with_backup_environment do |directory, environment|
      shared = File.join(directory, "shared")
      Dir.mkdir(shared)
      File.chmod(0o1777, shared)
      marker = File.join(shared, "keep.txt")
      File.write(marker, "existing")

      _output, error, status = run_backup(environment.merge("BACKUP_DIRECTORY" => shared, "DUMP_PAYLOAD" => "new"))

      assert_not status.success?
      assert_includes error, "mode 700"
      assert_equal 0o1777, File.stat(shared).mode & 0o7777
      assert_equal [ "keep.txt" ], Dir.children(shared)
      assert_equal "existing", File.read(marker)
    end
  end

  test "a new directory is created privately" do
    with_backup_environment do |directory, environment|
      destination = File.join(directory, "new", "backups")

      _output, error, status = run_backup(environment.merge("BACKUP_DIRECTORY" => destination, "DUMP_PAYLOAD" => "new"))

      assert status.success?, error
      assert_equal 0o700, File.stat(destination).mode & 0o7777
      assert_equal 0o700, File.stat(File.dirname(destination)).mode & 0o7777
      assert_equal 1, Dir.glob(File.join(destination, "leave-desk-*.dump")).size
    end
  end

  test "a failed backup preserves an existing private directory and its contents" do
    with_backup_environment do |directory, environment|
      marker = File.join(directory, "keep.txt")
      File.write(marker, "existing")
      original_mode = File.stat(directory).mode & 0o7777

      _output, _error, status = run_backup(environment.merge("DUMP_PAYLOAD" => "partial", "DUMP_FAIL" => "yes"))

      assert_not status.success?
      assert_equal original_mode, File.stat(directory).mode & 0o7777
      assert_equal "existing", File.read(marker)
      assert_empty Dir.glob(File.join(directory, ".leave-desk-*"))
    end
  end

  test "a missing checksum command is reported before creating a directory" do
    with_backup_environment do |directory, environment|
      isolated_bin = File.join(directory, "isolated-bin")
      Dir.mkdir(isolated_bin)
      %w[bash dirname realpath mkdir stat id date mktemp basename ln rm].each do |name|
        File.symlink(executable_path(name), File.join(isolated_bin, name))
      end
      File.symlink(File.join(directory, "bin", "pg_dump"), File.join(isolated_bin, "pg_dump"))
      destination = File.join(directory, "not-created")

      _output, error, status = run_backup(environment.merge("PATH" => isolated_bin, "BACKUP_DIRECTORY" => destination))

      assert_not status.success?
      assert_includes error, "requires sha256sum in PATH"
      assert_not File.exist?(destination)
    end
  end

  test "an unavailable Bash capability is reported before creating a directory" do
    with_backup_environment do |directory, environment|
      destination = File.join(directory, "not-created")
      script = Rails.root.join("bin/backup").to_s

      _output, error, status = Open3.capture3(environment.merge("BACKUP_DIRECTORY" => destination),
                                              "bash", "-c", 'enable -n mapfile; source "$1"', "bash", script)

      assert_not status.success?
      assert_includes error, "requires Bash 4 or newer"
      assert_not File.exist?(destination)
    end
  end

  private

  def executable_path(name)
    ENV.fetch("PATH").split(File::PATH_SEPARATOR).map { |path| File.join(path, name) }.find { |path| File.executable?(path) }
  end

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
