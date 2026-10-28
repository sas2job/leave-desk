require "test_helper"
require "fileutils"
require "open3"
require "tmpdir"

class RollbackTest < ActiveSupport::TestCase
  IMAGE = "ghcr.io/example/leave-desk@sha256:#{'b' * 64}"
  LEGACY_IMAGE = "ghcr.io/example/leave-desk:#{'c' * 40}"
  TOKEN = "test-token-that-must-not-be-logged"

  test "uses a cached private image without credentials or a registry pull" do
    with_rollback_environment(cached: true) do |root, environment|
      output, error, status = rollback(root, environment:, stdin_data: "unused secret\n")

      assert status.success?, error
      assert_includes output, "Using cached rollback image"
      assert_current_release root, "old-release"
      assert_equal [ "image inspect #{IMAGE}" ], docker_actions(environment)
      assert_equal [ "config --quiet", "up -d --no-deps --pull never web" ],
        compose_actions(environment)
      assert_empty credential_directories(environment)
    end
  end

  test "keeps cached legacy SHA-tag releases available during transition" do
    with_rollback_environment(cached: true, image: LEGACY_IMAGE) do |root, environment|
      _output, error, status = rollback(root, environment:, stdin_data: "")

      assert status.success?, error
      assert_current_release root, "old-release"
      assert_equal [ "image inspect #{LEGACY_IMAGE}" ], docker_actions(environment)
    end
  end

  test "pulls a missing private image with ephemeral stdin credentials" do
    with_rollback_environment(cached: false) do |root, environment|
      output, error, status = rollback(root, username: "operator", environment:,
        stdin_data: "#{TOKEN}\n")

      assert status.success?, "#{output}\n#{error}"
      assert_current_release root, "old-release"
      actions = docker_actions(environment)
      assert_equal "image inspect #{IMAGE}", actions.first
      assert actions.any? { |action| action.include?("login ghcr.io --username operator --password-stdin") }
      assert actions.any? { |action| action.end_with?("pull #{IMAGE}") }
      assert_equal "image inspect #{IMAGE}", actions.last
      assert_not_includes File.read(environment.fetch("DOCKER_LOG")), TOKEN
      assert_empty credential_directories(environment)
      assert_equal [ "config --quiet", "up -d --no-deps --pull never web" ],
        compose_actions(environment)
    end
  end

  test "missing image without credentials leaves current release untouched" do
    with_rollback_environment(cached: false) do |root, environment|
      _output, error, status = rollback(root, environment:, stdin_data: "")

      assert_not status.success?
      assert_includes error, "provide a GHCR username and token on stdin"
      assert_current_release root, "new-release"
      assert_empty compose_actions(environment)
      assert_empty credential_directories(environment)
    end
  end

  test "failed authenticated pull removes credentials and leaves current untouched" do
    with_rollback_environment(cached: false) do |root, environment|
      _output, _error, status = rollback(root, username: "operator",
        environment: environment.merge("FAIL_PULL" => "yes"), stdin_data: "#{TOKEN}\n")

      assert_not status.success?
      assert_current_release root, "new-release"
      assert_not_includes File.read(environment.fetch("DOCKER_LOG")), TOKEN
      assert_empty credential_directories(environment)
      assert_empty compose_actions(environment)
    end
  end

  private

  def with_rollback_environment(cached:, image: IMAGE)
    Dir.mktmpdir("leave-desk-rollback-test") do |root|
      new_release = File.join(root, "releases", "new-release")
      old_release = File.join(root, "releases", "old-release")
      executable_directory = File.join(root, "bin")
      runtime_directory = File.join(root, "runtime")
      FileUtils.mkdir_p([ new_release, old_release, executable_directory, runtime_directory ])
      File.symlink("releases/new-release", File.join(root, "current"))
      File.write(File.join(old_release, "release.env"), "LEAVE_DESK_IMAGE=#{image}\n")
      write_fake_compose(old_release)
      write_fake_docker(executable_directory)

      environment = {
        "LEAVE_DESK_DEPLOYMENT_ROOT" => root,
        "ROLLBACK_RUNTIME_DIRECTORY" => runtime_directory,
        "PATH" => "#{executable_directory}:#{ENV.fetch('PATH')}",
        "DOCKER_LOG" => File.join(root, "docker.log"),
        "COMPOSE_LOG" => File.join(root, "compose.log"),
        "IMAGE_MARKER" => File.join(root, "image-cached"),
        "EXPECTED_TOKEN" => TOKEN
      }
      FileUtils.touch(environment.fetch("IMAGE_MARKER")) if cached
      yield root, environment
    end
  end

  def write_fake_compose(release)
    executable = File.join(release, "compose.sh")
    File.write(executable, <<~'SH')
      #!/bin/sh
      printf '%s\n' "$*" >> "$COMPOSE_LOG"
    SH
    FileUtils.chmod(0o755, executable)
  end

  def write_fake_docker(directory)
    executable = File.join(directory, "docker")
    File.write(executable, <<~'SH')
      #!/bin/sh
      set -eu
      printf '%s\n' "$*" >> "$DOCKER_LOG"

      configuration=
      if [ "${1-}" = --config ]; then
        configuration=$2
        shift 2
      fi

      if [ "${1-} ${2-}" = "image inspect" ]; then
        test -f "$IMAGE_MARKER"
        exit
      fi

      case "${1-}" in
        login)
          IFS= read -r token
          test "$token" = "$EXPECTED_TOKEN"
          printf 'temporary credentials\n' > "$configuration/config.json"
          ;;
        pull)
          if [ "${FAIL_PULL:-}" = yes ]; then
            exit 1
          fi
          touch "$IMAGE_MARKER"
          ;;
        logout)
          rm -f "$configuration/config.json"
          ;;
      esac
    SH
    FileUtils.chmod(0o755, executable)
  end

  def rollback(root, username: nil, environment:, stdin_data:)
    command = [ "sh", Rails.root.join("deploy/rollback.sh").to_s, "old-release" ]
    command << username if username
    Open3.capture3(environment, *command, stdin_data:)
  end

  def assert_current_release(root, release)
    assert_equal File.join(root, "releases", release), File.realpath(File.join(root, "current"))
  end

  def docker_actions(environment)
    log = environment.fetch("DOCKER_LOG")
    File.exist?(log) ? File.readlines(log, chomp: true) : []
  end

  def compose_actions(environment)
    log = environment.fetch("COMPOSE_LOG")
    File.exist?(log) ? File.readlines(log, chomp: true) : []
  end

  def credential_directories(environment)
    Dir.glob(File.join(environment.fetch("ROLLBACK_RUNTIME_DIRECTORY"), "leave-desk-rollback-docker.*"))
  end
end
