require "test_helper"
require "digest"
require "fileutils"
require "open3"
require "tmpdir"

class RestoreScriptTest < ActiveSupport::TestCase
  test "restores an archive only after checking its matching sidecar" do
    with_restore_environment do |directory, environment, calls|
      archive = create_archive(directory, "leave-desk.dump", "valid archive")

      output, error, status = run_restore(environment, archive)

      assert status.success?, "#{output}\n#{error}"
      assert_equal "called\n", File.read(calls)
    end
  end

  test "rejects a damaged selected archive before pg_restore" do
    with_restore_environment do |directory, environment, calls|
      archive = create_archive(directory, "leave-desk.dump", "valid archive")
      File.binwrite(archive, "damaged archive")

      _output, _error, status = run_restore(environment, archive)

      assert_not status.success?
      assert_not File.exist?(calls)
    end
  end

  test "rejects a renamed pair while the original archive still exists" do
    with_restore_environment do |directory, environment, calls|
      original = create_archive(directory, "leave-desk.dump", "valid archive")
      renamed = File.join(directory, "renamed.dump")
      FileUtils.cp(original, renamed)
      FileUtils.cp("#{original}.sha256", "#{renamed}.sha256")

      _output, _error, status = run_restore(environment, renamed)

      assert_not status.success?
      assert_not File.exist?(calls)
    end
  end

  test "rejects a sidecar with more than one entry" do
    with_restore_environment do |directory, environment, calls|
      archive = create_archive(directory, "leave-desk.dump", "valid archive")
      File.open("#{archive}.sha256", "a") { |file| file.puts "#{'0' * 64}  other.dump" }

      _output, _error, status = run_restore(environment, archive)

      assert_not status.success?
      assert_not File.exist?(calls)
    end
  end

  private

  def with_restore_environment
    Dir.mktmpdir("leave-desk-restore-test") do |directory|
      executable_directory = File.join(directory, "bin")
      FileUtils.mkdir_p(executable_directory)
      restore = File.join(executable_directory, "pg_restore")
      File.write(restore, "#!/bin/sh\nprintf 'called\\n' >> \"$RESTORE_CALLS\"\n")
      FileUtils.chmod(0o700, restore)
      calls = File.join(directory, "restore-calls")
      environment = { "PATH" => "#{executable_directory}:#{ENV.fetch('PATH')}",
                      "RESTORE_CALLS" => calls,
                      "RESTORE_DATABASE_URL" => "postgres://localhost/isolated",
                      "ALLOW_DATABASE_RESTORE" => "yes" }
      yield directory, environment, calls
    end
  end

  def create_archive(directory, name, contents)
    archive = File.join(directory, name)
    File.binwrite(archive, contents)
    File.write("#{archive}.sha256", "#{Digest::SHA256.hexdigest(contents)}  #{name}\n")
    archive
  end

  def run_restore(environment, archive)
    Open3.capture3(environment, Rails.root.join("bin/restore").to_s, archive)
  end
end
