require "test_helper"
require "fileutils"
require "open3"
require "socket"
require "timeout"
require "tmpdir"

class WaitForHealthTest < ActiveSupport::TestCase
  SCRIPT = Rails.root.join("deploy/wait-for-health.sh").to_s

  test "passes connection and response limits to every request" do
    Dir.mktmpdir("leave-desk-health-test") do |directory|
      arguments_file = File.join(directory, "curl-arguments")
      write_successful_curl(File.join(directory, "curl"))
      environment = {
        "PATH" => "#{directory}:#{ENV.fetch('PATH')}",
        "CURL_ARGUMENTS_FILE" => arguments_file,
        "HEALTH_CONNECT_TIMEOUT" => "3",
        "HEALTH_REQUEST_TIMEOUT" => "7"
      }

      _output, error, status = run_health_check(environment)

      assert status.success?, error
      assert_equal [
        "--fail", "--silent", "--show-error",
        "--connect-timeout", "3", "--max-time", "7",
        "--header", "Host: health.example", "http://127.0.0.1:3000/up"
      ], File.readlines(arguments_file, chomp: true)
    end
  end

  test "fails within the response limit when a listener never responds" do
    TCPServer.open("127.0.0.1", 0) do |server|
      accepted = Queue.new
      listener = Thread.new do
        socket = server.accept
        accepted << true
        sleep
      ensure
        socket&.close
      end
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      environment = {
        "HEALTH_ATTEMPTS" => "1",
        "HEALTH_CONNECT_TIMEOUT" => "1",
        "HEALTH_REQUEST_TIMEOUT" => "1",
        "HEALTH_RETRY_DELAY" => "0",
        "NO_PROXY" => "127.0.0.1",
        "no_proxy" => "127.0.0.1"
      }

      _output, error, status = Timeout.timeout(5) do
        run_health_check(environment, url: "http://127.0.0.1:#{server.addr[1]}/up")
      end
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

      Timeout.timeout(1) { accepted.pop }
      assert_not status.success?
      assert_operator elapsed, :<, 4
      assert_includes error, "Internal health check failed after 1 attempts"
    ensure
      listener&.kill
      listener&.join
    end
  end

  private

  def run_health_check(environment, url: "http://127.0.0.1:3000/up")
    Open3.capture3(environment, "sh", SCRIPT, url, "health.example")
  end

  def write_successful_curl(path)
    File.write(path, <<~'SH')
      #!/bin/sh
      printf '%s\n' "$@" > "$CURL_ARGUMENTS_FILE"
    SH
    FileUtils.chmod(0o755, path)
  end
end
