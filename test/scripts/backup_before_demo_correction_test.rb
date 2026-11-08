require "minitest/autorun"
require "open3"
require "shellwords"
require "tmpdir"

class BackupBeforeDemoCorrectionTest < Minitest::Test
  def test_streamed_remote_script_finishes_even_when_docker_reads_stdin
    Dir.mktmpdir("demo-backup-test") do |directory|
      deployment = File.join(directory, "deployment")
      backup_root = File.join(directory, "backups")
      commands = File.join(directory, "commands")
      [ deployment, File.join(deployment, "current"), backup_root, commands ].each { |path| Dir.mkdir(path) }
      compose = File.join(deployment, "current/compose.sh")
      File.write(compose, <<~BASH)
        #!/usr/bin/env bash
        set -eu
        cat > /dev/null
        case "$*" in
          *psql*) printf '1024\\n' ;;
          *pg_dump*) printf 'synthetic archive\\n' ;;
          *pg_restore*) : ;;
          *) exit 64 ;;
        esac
      BASH
      File.chmod(0o700, compose)
      df = File.join(commands, "df")
      File.write(df, "#!/bin/sh\nprintf 'Avail\\n42949672960\\n'\n")
      File.chmod(0o700, df)
      source = File.read(File.expand_path("../../deploy/backup-before-demo-correction.sh", __dir__))
        .sub("cd /root/projects/leave-desk", "cd #{Shellwords.escape(deployment)}")
        .sub("backup_root=/var/backups/leave-desk", "backup_root=#{Shellwords.escape(backup_root)}")
      output, errors, status = Open3.capture3({ "PATH" => "#{commands}:#{ENV.fetch('PATH')}" },
        "bash", "-se", stdin_data: source)

      assert status.success?, errors
      assert_includes output, "Correction backup verified:"
      assert_includes output, "database.dump: OK"
      assert_equal 1, Dir.glob(File.join(backup_root, "*/database.dump.sha256")).size
    end
  end
end
