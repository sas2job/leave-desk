require "test_helper"
require "digest"
require "fileutils"
require "open3"
require "tmpdir"

class PublishReleaseTest < ActiveSupport::TestCase
  RELEASE_FILES = %w[
    Caddyfile
    apply-caddy.sh
    backup.sh
    compose.sh
    compose.yml
    leave-desk-backup.service
    leave-desk-backup.timer
    leave-desk-cache-cleanup.service
    leave-desk-cache-cleanup.timer
    leave-desk-session-prune.service
    leave-desk-session-prune.timer
    publish-release.sh
    rollback.sh
    wait-for-health.sh
  ].freeze
  IMAGE = "ghcr.io/example/leave-desk:#{'a' * 40}"

  test "publishes a verified release through one current symlink switch" do
    with_staged_release do |root, staging, environment|
      _output, error, status = publish(root, staging, environment:)

      assert status.success?, error
      release = File.join(root, "releases", "new-release")
      assert_equal release, File.realpath(File.join(root, "current"))
      assert_equal "LEAVE_DESK_IMAGE=#{IMAGE}\n", File.read(File.join(release, "release.env"))
      assert_equal "old release", File.read(File.join(root, "releases", "old-release", "marker"))
      assert_not File.exist?(staging)
    end
  end

  test "rejects a truncated transfer without changing current" do
    with_staged_release do |root, staging, environment|
      File.write(File.join(staging, "compose.yml"), "truncated")

      _output, _error, status = publish(root, staging, environment:)

      assert_not status.success?
      assert_equal File.join(root, "releases", "old-release"),
        File.realpath(File.join(root, "current"))
      assert_not File.exist?(File.join(root, "releases", "new-release"))
    end
  end

  test "failed final switch leaves the old release active and the new release complete" do
    with_staged_release do |root, staging, environment|
      fake_bin = File.join(root, "fake-bin")
      FileUtils.mkdir(fake_bin)
      write_failing_mv(File.join(fake_bin, "mv"))

      _output, _error, status = publish(root, staging,
        environment: environment.merge("PATH" => "#{fake_bin}:#{ENV.fetch('PATH')}"))

      assert_not status.success?
      assert_equal File.join(root, "releases", "old-release"),
        File.realpath(File.join(root, "current"))
      release = File.join(root, "releases", "new-release")
      assert_equal Rails.root.join("deploy/compose.yml").read,
        File.read(File.join(release, "compose.yml"))
      assert_equal "LEAVE_DESK_IMAGE=#{IMAGE}\n", File.read(File.join(release, "release.env"))
    end
  end

  test "rejects a staging directory outside the deployment tree" do
    Dir.mktmpdir("leave-desk-release-root") do |root|
      Dir.mktmpdir("leave-desk-external-stage") do |staging|
        FileUtils.mkdir(File.join(root, ".incoming"))
        _output, error, status = publish(root, staging, environment: {})

        assert_equal 64, status.exitstatus
        assert_includes error, "Staging directory must be below"
      end
    end
  end

  private

  def with_staged_release
    Dir.mktmpdir("leave-desk-release-test") do |root|
      old_release = File.join(root, "releases", "old-release")
      staging = File.join(root, ".incoming", "new-release")
      FileUtils.mkdir_p([ old_release, staging ])
      File.write(File.join(old_release, "marker"), "old release")
      File.symlink("releases/old-release", File.join(root, "current"))

      RELEASE_FILES.each do |file|
        source = Rails.root.join("deploy", file)
        FileUtils.cp(source, File.join(staging, file))
      end
      write_manifest(staging)

      yield root, staging, {}
    end
  end

  def write_manifest(staging)
    manifest = RELEASE_FILES.map do |file|
      digest = Digest::SHA256.file(File.join(staging, file)).hexdigest
      "#{digest}  #{file}"
    end
    File.write(File.join(staging, "SHA256SUMS"), "#{manifest.join("\n")}\n")
  end

  def write_failing_mv(path)
    File.write(path, <<~'SH')
      #!/bin/sh
      for argument do
        destination=$argument
      done
      case "$destination" in
        */current) exit 73 ;;
      esac
      exec /usr/bin/mv "$@"
    SH
    FileUtils.chmod(0o755, path)
  end

  def publish(root, staging, environment:)
    Open3.capture3(environment, "sh", Rails.root.join("deploy/publish-release.sh").to_s,
      root, staging, "new-release", IMAGE)
  end
end
