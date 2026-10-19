require "test_helper"
require "fileutils"
require "open3"
require "tmpdir"

class ComposeCommandTest < ActiveSupport::TestCase
  test "pins configuration and image environment to the resolved release" do
    Dir.mktmpdir("leave-desk-compose-command") do |root|
      release = File.join(root, "releases", "release-a")
      executable_directory = File.join(root, "bin")
      FileUtils.mkdir_p([ release, executable_directory ])
      FileUtils.cp(Rails.root.join("deploy/compose.sh"), release)
      File.write(File.join(release, "compose.yml"), "services: {}\n")
      File.write(File.join(release, "release.env"), "LEAVE_DESK_IMAGE=image-a\n")
      File.write(File.join(root, ".env"), "SECRET_KEY_BASE=secret\n")
      File.symlink("releases/release-a", File.join(root, "current"))
      write_fake_docker(executable_directory)

      arguments = File.join(root, "arguments")
      environment = {
        "PATH" => "#{executable_directory}:#{ENV.fetch('PATH')}",
        "DOCKER_ARGUMENTS" => arguments
      }
      _output, error, status = Open3.capture3(environment, "sh",
        File.join(root, "current", "compose.sh"), "config", "--quiet")

      assert status.success?, error
      assert_equal [
        "compose",
        "--project-directory", root,
        "--env-file", File.join(root, ".env"),
        "--env-file", File.join(release, "release.env"),
        "-f", File.join(release, "compose.yml"),
        "config", "--quiet"
      ], File.readlines(arguments, chomp: true)
    end
  end

  private

  def write_fake_docker(directory)
    executable = File.join(directory, "docker")
    File.write(executable, <<~'SH')
      #!/bin/sh
      printf '%s\n' "$@" > "$DOCKER_ARGUMENTS"
    SH
    FileUtils.chmod(0o755, executable)
  end
end
