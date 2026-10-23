require "test_helper"
require "fileutils"
require "open3"
require "tmpdir"
require "yaml"

class InstallMaintenanceTimersTest < ActiveSupport::TestCase
  test "installs released units and verifies a successful trial run" do
    with_fake_systemd do |script, unit_directory, environment|
      output, error, status = Open3.capture3(environment, "sh", script)

      assert status.success?, error
      %w[backup cache-cleanup].product(%w[service timer]).each do |name, extension|
        unit = "leave-desk-#{name}.#{extension}"
        assert_equal Rails.root.join("deploy", unit).read,
          File.read(File.join(unit_directory, unit))
      end
      assert_includes output, "Backup and cache cleanup timers active"
      actions = File.readlines(environment.fetch("SYSTEMCTL_LOG"), chomp: true)
      assert_operator actions.index("daemon-reload"), :<,
        actions.index("start leave-desk-cache-cleanup.service")
      assert_includes actions, "enable --now leave-desk-backup.timer"
      assert_includes actions, "enable --now leave-desk-cache-cleanup.timer"
    end
  end

  test "fails deployment if the cache cleanup trial run fails" do
    with_fake_systemd do |script, _unit_directory, environment|
      output, _error, status = Open3.capture3(
        environment.merge("FAIL_TRIAL" => "yes"), "sh", script
      )

      assert_not status.success?, output
      assert_not_includes output, "trial run succeeded"
    end
  end

  test "fails before cache trial if backup timer is inactive" do
    with_fake_systemd do |script, _unit_directory, environment|
      output, _error, status = Open3.capture3(
        environment.merge("FAIL_BACKUP_TIMER" => "yes"), "sh", script
      )

      assert_not status.success?, output
      actions = File.readlines(environment.fetch("SYSTEMCTL_LOG"), chomp: true)
      assert_not_includes actions, "start leave-desk-cache-cleanup.service"
    end
  end

  test "deployment runs installation after internal health check" do
    steps = YAML.load_file(Rails.root.join(".github/workflows/deploy.yml"))
      .fetch("jobs").fetch("deploy").fetch("steps")
    publish = steps.find { |step| step["name"] == "Publish deployment configuration atomically" }
    deploy = steps.find { |step| step["name"] == "Deploy tested image" }

    assert_includes publish.fetch("run"), "install-maintenance-timers.sh"
    commands = deploy.fetch("run")
    assert_operator commands.index("wait-for-health.sh"), :<,
      commands.index("./current/install-maintenance-timers.sh")
  end

  private

  def with_fake_systemd
    Dir.mktmpdir("leave-desk-maintenance-timer-test") do |root|
      release = File.join(root, "release")
      bin = File.join(root, "bin")
      unit_directory = File.join(root, "systemd")
      FileUtils.mkdir_p([ release, bin, unit_directory ])
      script = File.join(release, "install-maintenance-timers.sh")
      %w[install-maintenance-timers.sh leave-desk-backup.service leave-desk-backup.timer
        leave-desk-cache-cleanup.service leave-desk-cache-cleanup.timer].each do |file|
        FileUtils.cp(Rails.root.join("deploy", file), File.join(release, file))
      end
      File.write(File.join(bin, "systemctl"), <<~'SH')
        #!/bin/sh
        printf '%s\n' "$*" >> "$SYSTEMCTL_LOG"
        if [ "$1" = start ] && [ "${FAIL_TRIAL:-}" = yes ]; then
          exit 71
        fi
        if [ "$1" = is-active ] && [ "$3" = leave-desk-backup.timer ] && [ "${FAIL_BACKUP_TIMER:-}" = yes ]; then
          exit 72
        fi
        if [ "$1" = show ]; then
          case "$4" in
            FragmentPath) printf '%s/%s\n' "$LEAVE_DESK_SYSTEMD_DIRECTORY" "$2" ;;
            Result) printf 'success\n' ;;
            ExecMainStatus) printf '0\n' ;;
            *) exit 2 ;;
          esac
        fi
      SH
      FileUtils.chmod(0o755, File.join(bin, "systemctl"))
      environment = {
        "PATH" => "#{bin}:#{ENV.fetch('PATH')}",
        "LEAVE_DESK_SYSTEMD_DIRECTORY" => unit_directory,
        "SYSTEMCTL_LOG" => File.join(root, "systemctl.log")
      }
      yield script, unit_directory, environment
    end
  end
end
