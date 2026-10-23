require "test_helper"
require "fileutils"
require "open3"
require "tmpdir"

class ComposeLoggingTest < ActiveSupport::TestCase
  test "every long-lived service has bounded Docker logs" do
    services = YAML.safe_load_file(Rails.root.join("deploy/compose.yml"), aliases: true).fetch("services")
    expected = { "driver" => "json-file", "options" => { "max-size" => "10m", "max-file" => "3" } }

    %w[caddy db web].each do |service|
      assert_equal expected, services.fetch(service).fetch("logging"), "#{service} logging"
    end
  end

  test "deployment verifies effective logging for every long-lived container" do
    with_fake_containers do |script, environment|
      output, error, status = Open3.capture3(environment, "sh", script)

      assert status.success?, error
      assert_includes output, "caddy, db and web"
    end
  end

  test "deployment rejects a container whose effective logging is unbounded" do
    with_fake_containers do |script, environment|
      output, error, status = Open3.capture3(
        environment.merge("MISMATCH_SERVICE" => "db"), "sh", script
      )

      assert_not status.success?, output
      assert_includes error, "for db"
      assert_not_includes error, "container-db"
    end
  end

  test "deployment publishes and runs the effective logging check" do
    steps = YAML.load_file(Rails.root.join(".github/workflows/deploy.yml"))
      .fetch("jobs").fetch("deploy").fetch("steps")
    publish = steps.find { |step| step["name"] == "Publish deployment configuration atomically" }
    deploy = steps.find { |step| step["name"] == "Deploy tested image" }

    assert_includes publish.fetch("run"), "verify-container-logging.sh"
    commands = deploy.fetch("run")
    assert_operator commands.index("./current/apply-caddy.sh"), :<,
      commands.index("./current/verify-container-logging.sh")
  end

  private

  def with_fake_containers
    Dir.mktmpdir("leave-desk-logging-test") do |root|
      release = File.join(root, "release")
      bin = File.join(root, "bin")
      FileUtils.mkdir_p([ release, bin ])
      script = File.join(release, "verify-container-logging.sh")
      FileUtils.cp(Rails.root.join("deploy/verify-container-logging.sh"), script)
      File.write(File.join(release, "compose.sh"), <<~'SH')
        #!/bin/sh
        [ "$1" = ps ] && [ "$2" = -q ] || exit 2
        printf 'container-%s\n' "$3"
      SH
      File.write(File.join(bin, "docker"), <<~'SH')
        #!/bin/sh
        [ "$1" = inspect ] && [ "$2" = --format ] || exit 2
        service=${4#container-}
        if [ "$service" = "${MISMATCH_SERVICE:-}" ]; then
          printf 'json-file 10m 0\n'
        else
          printf 'json-file 10m 3\n'
        fi
      SH
      FileUtils.chmod(0o755, File.join(release, "compose.sh"))
      FileUtils.chmod(0o755, File.join(bin, "docker"))
      yield script, { "PATH" => "#{bin}:#{ENV.fetch('PATH')}" }
    end
  end
end
