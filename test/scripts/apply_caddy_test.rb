require "test_helper"
require "fileutils"
require "open3"
require "tmpdir"

class ApplyCaddyTest < ActiveSupport::TestCase
  test "valid candidate is applied, reconciled and reloaded" do
    with_deployment do |directory, environment|
      File.write(File.join(directory, "Caddyfile.next"), "new configuration")

      _output, error, status = run_apply(directory, environment)

      assert status.success?, error
      assert_equal "new configuration", File.read(File.join(directory, "Caddyfile"))
      assert_equal [ "run", "up", "exec" ], docker_actions(environment)
    end
  end

  test "invalid candidate leaves active configuration untouched" do
    with_deployment do |directory, environment|
      File.write(File.join(directory, "Caddyfile.next"), "INVALID")

      _output, _error, status = run_apply(directory, environment)

      assert_not status.success?
      assert_equal "old configuration", File.read(File.join(directory, "Caddyfile"))
      assert_equal [ "run" ], docker_actions(environment)
    end
  end

  test "failed reload restores active configuration" do
    with_deployment do |directory, environment|
      File.write(File.join(directory, "Caddyfile.next"), "new configuration")

      _output, _error, status = run_apply(directory,
        environment.merge("FAIL_RELOAD_FOR_NEW_CONFIG" => "yes"))

      assert_not status.success?
      assert_equal "old configuration", File.read(File.join(directory, "Caddyfile"))
      assert_equal [ "run", "up", "exec", "up", "exec" ], docker_actions(environment)
    end
  end

  private

  def with_deployment
    Dir.mktmpdir("leave-desk-caddy-test") do |directory|
      executable_directory = File.join(directory, "bin")
      FileUtils.mkdir_p(executable_directory)
      FileUtils.cp(Rails.root.join("deploy/apply-caddy.sh"), directory)
      File.write(File.join(directory, "Caddyfile"), "old configuration")
      docker = File.join(executable_directory, "docker")
      File.write(docker, <<~'SH')
        #!/bin/sh
        printf '%s\n' "$2" >> "$DOCKER_LOG"
        if [ "$2" = run ] && grep -q INVALID Caddyfile.next; then
          exit 1
        fi
        if [ "$2" = exec ] && [ "${FAIL_RELOAD_FOR_NEW_CONFIG:-}" = yes ] &&
            grep -q 'new configuration' Caddyfile; then
          exit 1
        fi
      SH
      FileUtils.chmod(0o755, docker)
      environment = { "PATH" => "#{executable_directory}:#{ENV.fetch('PATH')}",
        "DOCKER_LOG" => File.join(directory, "docker.log") }
      yield directory, environment
    end
  end

  def run_apply(directory, environment)
    Open3.capture3(environment, "sh", File.join(directory, "apply-caddy.sh"))
  end

  def docker_actions(environment)
    File.readlines(environment.fetch("DOCKER_LOG"), chomp: true)
  end
end
