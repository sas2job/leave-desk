require "test_helper"
require "fileutils"
require "open3"
require "tmpdir"
require "yaml"

class SchemaCompatibilityTest < ActiveSupport::TestCase
  GENERATION = "20261014144746"
  OLDER_GENERATION = "20261001000000"

  test "stops the old writer before migration and raises the rollback floor" do
    with_migration_environment do |root, release, environment|
      output, error, status = apply_migrations(release, environment:)

      assert status.success?, "#{output}\n#{error}"
      assert_equal [ "stop web", "run --rm migrate" ], compose_actions(environment)
      assert_equal "#{GENERATION}\n", File.read(File.join(root, "schema-rollback-floor"))
      assert_includes output, "Schema rollback floor: #{GENERATION}"
    end
  end

  test "leaves the writer stopped and the rollback floor unchanged when migration fails" do
    with_migration_environment(floor: OLDER_GENERATION) do |root, release, environment|
      output, error, status = apply_migrations(
        release,
        environment: environment.merge("FAIL_MIGRATION" => "yes")
      )

      assert_not status.success?, output
      assert_includes error, "web remains stopped"
      assert_equal [ "stop web", "run --rm migrate" ], compose_actions(environment)
      assert_equal "#{OLDER_GENERATION}\n",
        File.read(File.join(root, "schema-rollback-floor"))
    end
  end

  test "rejects rollback below the applied floor before Docker or Compose side effects" do
    Dir.mktmpdir("leave-desk-schema-rollback-test") do |root|
      current_release = File.join(root, "releases", "current-release")
      target_release = File.join(root, "releases", "old-release")
      executable_directory = File.join(root, "bin")
      FileUtils.mkdir_p([ current_release, target_release, executable_directory ])
      File.symlink("releases/current-release", File.join(root, "current"))
      File.write(File.join(root, "schema-rollback-floor"), "#{GENERATION}\n")
      File.write(File.join(target_release, "schema-compatibility"), "#{OLDER_GENERATION}\n")
      File.write(File.join(target_release, "release.env"),
        "LEAVE_DESK_IMAGE=ghcr.io/example/leave-desk@sha256:#{'a' * 64}\n")
      write_logging_executable(File.join(target_release, "compose.sh"), "COMPOSE_LOG")
      write_logging_executable(File.join(executable_directory, "docker"), "DOCKER_LOG")

      environment = {
        "LEAVE_DESK_DEPLOYMENT_ROOT" => root,
        "PATH" => "#{executable_directory}:#{ENV.fetch('PATH')}",
        "COMPOSE_LOG" => File.join(root, "compose.log"),
        "DOCKER_LOG" => File.join(root, "docker.log")
      }
      output, error, status = Open3.capture3(
        environment,
        "sh",
        Rails.root.join("deploy/rollback.sh").to_s,
        "old-release"
      )

      assert_not status.success?, output
      assert_includes error, "below rollback floor #{GENERATION}"
      assert_equal current_release, File.realpath(File.join(root, "current"))
      assert_not File.exist?(environment.fetch("COMPOSE_LOG"))
      assert_not File.exist?(environment.fetch("DOCKER_LOG"))
    end
  end

  test "workflow publishes compatibility metadata and applies the migration boundary" do
    workflow = YAML.load_file(Rails.root.join(".github/workflows/deploy.yml"))
    steps = workflow.fetch("jobs").fetch("deploy").fetch("steps")
    publish = steps.find { |step| step["name"] == "Publish deployment configuration atomically" }
    deploy = steps.find { |step| step["name"] == "Deploy tested image" }

    assert_includes publish.fetch("run"), "apply-migrations.sh"
    assert_includes publish.fetch("run"), "schema-compatibility"

    commands = deploy.fetch("run")
    pull_position = commands.index("./current/compose.sh pull web migrate")
    migrate_position = commands.index("./current/apply-migrations.sh")
    start_position = commands.index("./current/compose.sh up -d --no-deps web")

    assert pull_position, "image pull is missing"
    assert migrate_position, "migration boundary is missing"
    assert start_position, "web start is missing"
    assert_operator pull_position, :<, migrate_position
    assert_operator migrate_position, :<, start_position
    assert_not_includes commands, "./current/compose.sh run --rm migrate"
  end

  private

  def with_migration_environment(floor: nil)
    Dir.mktmpdir("leave-desk-schema-migration-test") do |root|
      release = File.join(root, "releases", "new-release")
      FileUtils.mkdir_p(release)
      FileUtils.cp(Rails.root.join("deploy/apply-migrations.sh"), release)
      File.write(File.join(release, "schema-compatibility"), "#{GENERATION}\n")
      write_migration_compose(File.join(release, "compose.sh"))
      File.write(File.join(root, "schema-rollback-floor"), "#{floor}\n") if floor

      environment = {
        "LEAVE_DESK_DEPLOYMENT_ROOT" => root,
        "COMPOSE_LOG" => File.join(root, "compose.log")
      }
      yield root, release, environment
    end
  end

  def write_migration_compose(path)
    File.write(path, <<~'SH')
      #!/bin/sh
      set -eu
      printf '%s\n' "$*" >> "$COMPOSE_LOG"
      if [ "$*" = "run --rm migrate" ] && [ "${FAIL_MIGRATION:-}" = yes ]; then
        exit 71
      fi
    SH
    FileUtils.chmod(0o755, path)
  end

  def write_logging_executable(path, log_variable)
    File.write(path, <<~SH)
      #!/bin/sh
      printf '%s\\n' "$*" >> "$#{log_variable}"
    SH
    FileUtils.chmod(0o755, path)
  end

  def apply_migrations(release, environment:)
    Open3.capture3(environment, "sh", File.join(release, "apply-migrations.sh"))
  end

  def compose_actions(environment)
    File.readlines(environment.fetch("COMPOSE_LOG"), chomp: true)
  end
end
