require "test_helper"
require "digest"
require "fileutils"
require "open3"
require "tmpdir"

class CheckPreResetBackupTest < ActiveSupport::TestCase
  test "selects the latest verified archive before the demo reset" do
    Dir.mktmpdir("leave-desk-backup-audit-test") do |directory|
      create_backup(directory, "20261019T020000Z")
      create_backup(directory, "20261020T020000Z")
      create_backup(directory, "20261021T020000Z")

      output, error, status = check(directory)

      assert status.success?, error
      assert_includes output, "Pre-reset backups: count=2; earliest=20261019T020000Z; latest=20261020T020000Z"
      assert_includes output, "leave-desk-20261020T020000Z; checksum: valid"
      assert_not_includes output, "20261021"
    end
  end

  test "reports missing and damaged archives without printing their contents" do
    Dir.mktmpdir("leave-desk-backup-audit-test") do |directory|
      output, error, status = check(directory)
      assert status.success?, error
      assert_includes output, "none retained"

      archive = create_backup(directory, "20261020T020000Z")
      File.write(File.join(archive, "database.dump"), "damaged")
      output, error, status = check(directory)
      assert_not status.success?, output
      assert_includes error, "checksum failed"
      assert_not_includes error, "damaged"
    end
  end

  private

  def create_backup(directory, stamp)
    archive = File.join(directory, "leave-desk-#{stamp}")
    FileUtils.mkdir_p(archive)
    File.write(File.join(archive, "database.dump"), "archive #{stamp}")
    digest = Digest::SHA256.file(File.join(archive, "database.dump")).hexdigest
    File.write(File.join(archive, "database.dump.sha256"), "#{digest}  database.dump\n")
    archive
  end

  def check(directory)
    Open3.capture3({ "LEAVE_DESK_BACKUP_DIRECTORY" => directory }, "bash",
      Rails.root.join("deploy/check-pre-reset-backup.sh").to_s)
  end
end
