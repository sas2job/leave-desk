require "test_helper"
require "open3"

class NoArgumentEntrypointsTest < ActiveSupport::TestCase
  COMMANDS = [
    [ RbConfig.ruby, "bin/first-administrator", 2 ],
    [ RbConfig.ruby, "bin/deploy-gate", 2 ],
    [ RbConfig.ruby, "bin/ci", 2 ],
    [ "bash", "bin/backup", 2 ],
    [ "bash", "bin/prepare-production-database", 2 ],
    [ "sh", "deploy/install-maintenance-timers.sh", 64 ],
    [ "sh", "deploy/apply-caddy.sh", 64 ],
    [ "bash", "deploy/audit-leave-history.sh", 64 ],
    [ "bash", "deploy/audit-pre-reset-backup.sh", 64 ],
    [ "bash", "deploy/backup-health.sh", 64 ],
    [ "bash", "deploy/backup.sh", 64 ],
    [ "bash", "deploy/check-pre-reset-backup.sh", 64 ],
    [ "sh", "deploy/verify-container-logging.sh", 64 ]
  ].freeze

  test "commands without arguments reject an option before starting work" do
    COMMANDS.each do |interpreter, script, expected_status|
      stdout, stderr, status = Open3.capture3(
        interpreter, Rails.root.join(script).to_s, "--unexpected"
      )

      assert_equal expected_status, status.exitstatus, script
      assert_empty stdout, script
      assert_includes stderr, "Usage:", script
      assert_no_match(/--unexpected/, stderr, script)
    end
  end

  test "setup rejects unknown or repeated options before installing dependencies" do
    [ [ "--unexpected" ], [ "--reset", "--reset" ] ].each do |arguments|
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, Rails.root.join("bin/setup").to_s, *arguments
      )

      assert_equal 2, status.exitstatus
      assert_empty stdout
      assert_includes stderr, "Usage: bin/setup [--reset] [--skip-server]"
    end
  end
end
