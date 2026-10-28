require "test_helper"
require "fileutils"
require "open3"
require "tmpdir"

class ApplyCaddyTest < ActiveSupport::TestCase
  test "compose mounts the stable Caddy configuration directory" do
    compose = YAML.safe_load_file(Rails.root.join("deploy/compose.yml"), aliases: true)
    volumes = compose.fetch("services").fetch("caddy").fetch("volumes")

    assert_includes volumes, "./caddy:/etc/caddy:ro"
    assert_not volumes.any? { |volume| volume.start_with?("./Caddyfile:") }
  end

  test "valid candidate is atomically published, reconciled and reloaded" do
    with_deployment do |directory, release, environment|
      File.write(File.join(release, "Caddyfile"), "new configuration")

      _output, error, status = run_apply(release, environment)

      assert status.success?, error
      assert_equal "new configuration", active_configuration(directory)
      assert_equal [ "run", "up", "exec" ], compose_actions(environment)
      assert_empty temporary_configurations(directory)
    end
  end

  test "invalid candidate leaves active configuration untouched" do
    with_deployment do |directory, release, environment|
      File.write(File.join(release, "Caddyfile"), "INVALID")

      _output, _error, status = run_apply(release, environment)

      assert_not status.success?
      assert_equal "old configuration", active_configuration(directory)
      assert_equal [ "run" ], compose_actions(environment)
      assert_empty temporary_configurations(directory)
    end
  end

  test "write failure leaves active configuration untouched" do
    with_deployment do |directory, release, environment|
      File.write(File.join(release, "Caddyfile"), "new configuration")
      configuration_directory = File.join(directory, "caddy")
      FileUtils.chmod(0o500, configuration_directory)

      _output, _error, status = run_apply(release, environment)

      assert_not status.success?
      assert_equal "old configuration", active_configuration(directory)
      assert_equal [ "run" ], compose_actions(environment)
    ensure
      FileUtils.chmod(0o700, configuration_directory)
    end
  end

  test "failed reload atomically restores active configuration" do
    with_deployment do |directory, release, environment|
      File.write(File.join(release, "Caddyfile"), "new configuration")

      _output, error, status = run_apply(release,
        environment.merge("FAIL_RELOAD_FOR_NEW_CONFIG" => "yes"))

      assert_not status.success?
      assert_includes error, "Caddy reload failed after admin endpoint became ready"
      assert_equal "old configuration", active_configuration(directory)
      assert_equal [ "run", "up", "exec", "up", "exec" ], compose_actions(environment)
      assert_empty temporary_configurations(directory)
    end
  end

  test "startup delay is retried before reloading valid configuration" do
    with_deployment do |directory, release, environment|
      File.write(File.join(release, "Caddyfile"), "new configuration")

      _output, error, status = run_apply(release,
        environment.merge("PROBE_FAILURES_BEFORE_READY" => "2"))

      assert status.success?, error
      assert_equal "new configuration", active_configuration(directory)
      assert_equal 3, File.readlines(environment.fetch("COMPOSE_LOG")).count("probe\n")
      assert_equal [ "run", "up", "exec" ], compose_actions(environment)
    end
  end

  test "unavailable admin endpoint times out and restores previous configuration" do
    with_deployment do |directory, release, environment|
      File.write(File.join(release, "Caddyfile"), "new configuration")

      _output, error, status = run_apply(release, environment.merge(
        "PROBE_ALWAYS_FAIL_FOR_NEW_CONFIG" => "yes",
        "LEAVE_DESK_CADDY_READY_TIMEOUT_SECONDS" => "1"
      ))

      assert_not status.success?
      assert_includes error, "Caddy admin endpoint unavailable after 1s"
      assert_equal "old configuration", active_configuration(directory)
      assert_equal [ "run", "up", "up", "exec" ], compose_actions(environment)
      assert_empty temporary_configurations(directory)
    end
  end

  test "failed container reconciliation atomically restores active configuration" do
    with_deployment do |directory, release, environment|
      File.write(File.join(release, "Caddyfile"), "new configuration")

      _output, _error, status = run_apply(release,
        environment.merge("FAIL_UP_FOR_NEW_CONFIG" => "yes"))

      assert_not status.success?
      assert_equal "old configuration", active_configuration(directory)
      assert_equal [ "run", "up", "up", "exec" ], compose_actions(environment)
      assert_empty temporary_configurations(directory)
    end
  end

  test "forced interruption leaves a complete configuration for the next restart" do
    with_deployment do |directory, release, environment|
      File.write(File.join(release, "Caddyfile"), "new configuration")

      _output, _error, status = run_apply(release,
        environment.merge("KILL_PARENT_ON_UP_FOR_NEW_CONFIG" => "yes"))

      assert status.signaled?
      assert_equal "new configuration", active_configuration(directory)

      _output, error, retry_status = run_apply(release, environment)
      assert retry_status.success?, error
      assert_equal "new configuration", active_configuration(directory)
    end
  end

  test "legacy single-file configuration is available for rollback" do
    with_deployment(active_configuration: false) do |directory, release, environment|
      File.write(File.join(directory, "Caddyfile"), "legacy configuration")
      File.write(File.join(release, "Caddyfile"), "new configuration")

      _output, _error, status = run_apply(release,
        environment.merge("FAIL_RELOAD_FOR_NEW_CONFIG" => "yes"))

      assert_not status.success?
      assert_equal "legacy configuration", active_configuration(directory)
      assert_equal "legacy configuration", File.read(File.join(directory, "Caddyfile"))
    end
  end

  private

  def with_deployment(active_configuration: true)
    Dir.mktmpdir("leave-desk-caddy-test") do |directory|
      release = File.join(directory, "releases", "new-release")
      configuration_directory = File.join(directory, "caddy")
      FileUtils.mkdir_p([ release, configuration_directory ])
      FileUtils.cp(Rails.root.join("deploy/apply-caddy.sh"), release)
      File.write(File.join(configuration_directory, "Caddyfile"), "old configuration") if active_configuration
      write_fake_compose(release)

      environment = {
        "LEAVE_DESK_DEPLOYMENT_ROOT" => directory,
        "COMPOSE_LOG" => File.join(directory, "compose.log"),
        "ACTIVE_CADDYFILE" => File.join(configuration_directory, "Caddyfile"),
        "CANDIDATE_CADDYFILE" => File.join(release, "Caddyfile")
      }
      yield directory, release, environment
    end
  end

  def write_fake_compose(release)
    compose = File.join(release, "compose.sh")
    File.write(compose, <<~'SH')
      #!/bin/sh
      set -eu
      action=$1
      if [ "$action" = exec ] && [ "${4:-}" = curl ]; then
        printf 'probe\n' >> "$COMPOSE_LOG"
        if [ "${PROBE_ALWAYS_FAIL_FOR_NEW_CONFIG:-}" = yes ] &&
          grep -q 'new configuration' "$ACTIVE_CADDYFILE"; then
          exit 7
        fi
        count=0
        if [ -f "$COMPOSE_LOG.probes" ]; then
          count=$(cat "$COMPOSE_LOG.probes")
        fi
        count=$((count + 1))
        printf '%s\n' "$count" > "$COMPOSE_LOG.probes"
        if [ "$count" -le "${PROBE_FAILURES_BEFORE_READY:-0}" ]; then
          exit 7
        fi
        exit 0
      fi
      printf '%s\n' "$action" >> "$COMPOSE_LOG"

      if [ "$action" = run ] && grep -q INVALID "$CANDIDATE_CADDYFILE"; then
        exit 1
      fi

      if [ "$action" = up ] && grep -q 'new configuration' "$ACTIVE_CADDYFILE"; then
        if [ "${KILL_PARENT_ON_UP_FOR_NEW_CONFIG:-}" = yes ]; then
          kill -KILL "$PPID"
          exit 1
        fi
        if [ "${FAIL_UP_FOR_NEW_CONFIG:-}" = yes ]; then
          exit 1
        fi
      fi

      if [ "$action" = exec ] &&
        [ "${FAIL_RELOAD_FOR_NEW_CONFIG:-}" = yes ] &&
        grep -q 'new configuration' "$ACTIVE_CADDYFILE"; then
        exit 1
      fi
    SH
    FileUtils.chmod(0o755, compose)
  end

  def run_apply(release, environment)
    Open3.capture3(environment, "sh", File.join(release, "apply-caddy.sh"))
  end

  def active_configuration(directory)
    File.read(File.join(directory, "caddy", "Caddyfile"))
  end

  def temporary_configurations(directory)
    Dir.glob(File.join(directory, "caddy", ".Caddyfile.*"))
  end

  def compose_actions(environment)
    File.readlines(environment.fetch("COMPOSE_LOG"), chomp: true).reject { |action| action == "probe" }
  end
end
