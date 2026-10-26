require "test_helper"
require "digest"
require "fileutils"
require "open3"
require "tmpdir"

class AuditPreResetBackupTest < ActiveSupport::TestCase
  test "restores an archive in an isolated container and prints only aggregates" do
    with_fake_commands do |environment|
      output, error, status = run_audit(environment)

      assert status.success?, error
      assert_includes output, "reviewed cancellations=2; valid histories=2; invalid histories=0"
      assert_includes output, "approvals without notifications=1"
      actions = File.read(environment.fetch("DOCKER_LOG"))
      assert_includes actions, "--network none"
      assert_includes actions, "-d audit -Atqc SELECT 1"
      assert_includes actions, "pg_restore"
      assert_includes actions, "--no-owner --no-privileges"
      assert_includes actions, "stop leave-desk-history-audit-test"
    end
  end

  test "rejects invalid history and stops the isolated container" do
    with_fake_commands do |environment|
      output, _error, status = run_audit(environment.merge("FAKE_COUNTS" => "2,1,1,0"))

      assert_not status.success?, output
      assert_includes output, "invalid histories=1"
      assert_includes File.read(environment.fetch("DOCKER_LOG")), "stop leave-desk-history-audit-test"
    end
  end

  test "waits until the isolated database accepts connections" do
    with_fake_commands do |environment|
      output, error, status = run_audit(environment.merge("FAKE_DB_READY_FAILURES" => "1"))
      assert status.success?, error
      assert_includes output, "valid histories=2"
      assert_equal 2, File.read(environment.fetch("DB_READY_LOG")).lines.count
    end
  end

  test "audits a selected pre-reset archive" do
    with_fake_commands do |environment|
      output, error, status = run_audit(environment.merge(
        "AUDIT_ARCHIVE_TIMESTAMP" => "20261019T020030Z"
      ))

      assert status.success?, error
      assert_includes output, "valid histories=2"
      assert_includes File.read(environment.fetch("SSH_LOG")),
        "leave-desk-20261019T020030Z/database.dump"
    end
  end

  test "rejects archive timestamps after the reset before connecting" do
    with_fake_commands do |environment|
      _output, error, status = run_audit(environment.merge(
        "AUDIT_ARCHIVE_TIMESTAMP" => "20261021T020030Z"
      ))

      assert_not status.success?
      assert_includes error, "Archive timestamp must precede the demo reset"
      assert_not File.exist?(environment.fetch("SSH_LOG"))
    end
  end

  test "classifies restore errors without exposing database details" do
    with_fake_commands do |environment|
      _output, error, status = run_audit(environment.merge(
        "FAKE_RESTORE_ERROR" => 'pg_restore: error: role "private-role" does not exist'
      ))

      assert_not status.success?
      assert_includes error, "missing database role"
      assert_not_includes error, "private-role"
    end
  end

  test "reports safe diagnostics for an unclassified restore error" do
    with_fake_commands do |environment|
      _output, error, status = run_audit(environment.merge(
        "FAKE_RESTORE_ERROR" => "private-name: database operation failed"
      ))
      assert_not status.success?
      assert_includes error, "unclassified restore error; exit=71; stderr_bytes="
      assert_includes error, "markers=database,failed"
      assert_not_includes error, "private-name"
    end
  end

  private

  def with_fake_commands
    Dir.mktmpdir("leave-desk-pre-reset-audit-test") do |directory|
      bin = File.join(directory, "bin")
      FileUtils.mkdir_p(bin)
      archive = File.join(directory, "source.dump")
      checksum = File.join(directory, "source.sha256")
      File.write(archive, "synthetic archive")
      File.write(checksum, "#{Digest::SHA256.file(archive).hexdigest}  database.dump\n")
      File.write(File.join(bin, "ssh"), <<~'SH')
        #!/bin/sh
        printf '%s\n' "$*" >> "$SSH_LOG"
        case "$*" in
          *database.dump.sha256*) cat "$FAKE_CHECKSUM" ;;
          *database.dump*) cat "$FAKE_ARCHIVE" ;;
          *) exit 2 ;;
        esac
      SH
      File.write(File.join(bin, "docker"), <<~'SH')
        #!/bin/sh
        printf '%s\n' "$*" >> "$DOCKER_LOG"
        case "$*" in
          run\ *) printf 'fake-container\n' ;;
          *'-Atqc SELECT 1'*)
            printf 'attempt\n' >> "$DB_READY_LOG"
            attempts=$(wc -l < "$DB_READY_LOG")
            if [ "$attempts" -le "${FAKE_DB_READY_FAILURES:-0}" ]; then exit 1; fi
            printf '1\n' ;;
          *pg_restore*)
            if [ -n "${FAKE_RESTORE_ERROR:-}" ]; then
              printf '%s\n' "$FAKE_RESTORE_ERROR" >&2
              exit 71
            fi
            cat >/dev/null ;;
          *psql*' -c '*) printf '%s\n' "$FAKE_WITHOUT_NOTIFICATION" ;;
          *psql*) cat >/dev/null; printf '%s\n' "$FAKE_COUNTS" ;;
          stop\ *) exit 0 ;;
          *) exit 2 ;;
        esac
      SH
      %w[ssh docker].each { |file| FileUtils.chmod(0o755, File.join(bin, file)) }
      yield({
        "PATH" => "#{bin}:#{ENV.fetch('PATH')}",
        "DEPLOY_HOST" => "example.test",
        "DEPLOY_PORT" => "22",
        "DEPLOY_USER" => "operator",
        "RUNNER_TEMP" => directory,
        "GITHUB_RUN_ID" => "test",
        "FAKE_ARCHIVE" => archive,
        "FAKE_CHECKSUM" => checksum,
        "FAKE_COUNTS" => "2,2,0,1",
        "FAKE_WITHOUT_NOTIFICATION" => "1",
        "DOCKER_LOG" => File.join(directory, "docker.log"),
        "SSH_LOG" => File.join(directory, "ssh.log"),
        "DB_READY_LOG" => File.join(directory, "db-ready.log")
      })
    end
  end

  def run_audit(environment)
    Open3.capture3(environment, "bash", Rails.root.join("deploy/audit-pre-reset-backup.sh").to_s)
  end
end
