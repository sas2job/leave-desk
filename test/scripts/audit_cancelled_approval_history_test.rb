require "test_helper"
require "fileutils"
require "open3"
require "tmpdir"
require "yaml"
require Rails.root.join("db/migrate/20261015103423_restore_cancelled_request_approval_events")

class AuditCancelledApprovalHistoryTest < ActiveSupport::TestCase
  test "counts only complete ordered histories and confirms the corrective migration" do
    employee = User.create!(name: "Employee", email_address: "audit-employee@example.test",
      password: "test-password")
    reviewer = User.create!(name: "Reviewer", email_address: "audit-reviewer@example.test",
      password: "test-password", role: :manager)
    leave_type = LeaveType.create!(name: "Annual", code: "AUDIT_ANNUAL")
    reviewed_at = Time.zone.local(2026, 10, 14, 13)
    cancelled_at = reviewed_at + 1.hour

    complete = request_for(employee, leave_type, 1, reviewer, reviewed_at)
    add_event(complete, reviewer, :approved, 0, 1, reviewed_at + 1.second, "Reviewed")
    add_event(complete, employee, :cancelled, 1, 3, cancelled_at)

    legacy = request_for(employee, leave_type, 3, reviewer, reviewed_at)
    add_event(legacy, employee, :cancelled, 0, 3, cancelled_at)

    assert_equal [ 2, 1, 1, 0 ], audit_counts

    RestoreCancelledRequestApprovalEvents.new.up

    assert_equal [ 2, 2, 0, 1 ], audit_counts
  end

  test "runner accepts aggregate counts without invalid histories" do
    with_fake_ssh("2,2,0,1") do |environment|
      output, error, status = run_audit(environment)

      assert status.success?, error
      assert_includes output, "invalid histories: 0"
    end
  end

  test "runner rejects invalid histories and malformed aggregates" do
    [ "2,1,1,0", "unexpected output" ].each do |response|
      with_fake_ssh(response) do |environment|
        _output, _error, status = run_audit(environment)

        assert_not status.success?
      end
    end
  end

  test "production audit is the last deployment step" do
    steps = YAML.load_file(Rails.root.join(".github/workflows/deploy.yml"))
      .fetch("jobs").fetch("deploy").fetch("steps")

    assert_equal "Audit leave history", steps.last.fetch("name")
    assert_equal "bash deploy/audit-leave-history.sh", steps.last.fetch("run")
  end

  private

  def request_for(employee, leave_type, day, reviewer, reviewed_at)
    date = Date.new(2026, 12, day)
    request = LeaveRequest.create!(employee:, leave_type:, starts_on: date, ends_on: date)
    request.update_columns(status: LeaveRequest.statuses.fetch("cancelled"),
      reviewer_id: reviewer.id, reviewed_at:, review_comment: "Reviewed")
    request
  end

  def add_event(request, actor, type, from_status, to_status, occurred_at, comment = nil)
    LeaveRequestEvent.insert_all!([ {
      leave_request_id: request.id,
      actor_id: actor.id,
      event_type: LeaveRequestEvent.event_types.fetch(type.to_s),
      from_status:, to_status:, occurred_at:, comment:
    } ])
  end

  def audit_counts
    sql = Rails.root.join("deploy/audit-cancelled-approval-history.sql").read
    result = ActiveRecord::Base.connection.select_one(sql)
    result.values_at("reviewed_cancelled", "valid_history", "invalid_history",
      "approvals_at_review_time").map(&:to_i)
  end

  def with_fake_ssh(response)
    Dir.mktmpdir("leave-desk-history-audit-test") do |directory|
      ssh = File.join(directory, "ssh")
      File.write(ssh, "#!/bin/sh\nprintf '%s\\n' \"$AUDIT_RESULT\"\n")
      FileUtils.chmod(0o755, ssh)
      yield({
        "PATH" => "#{directory}:#{ENV.fetch('PATH')}",
        "DEPLOY_HOST" => "example.test",
        "DEPLOY_PORT" => "22",
        "DEPLOY_USER" => "operator",
        "AUDIT_RESULT" => response
      })
    end
  end

  def run_audit(environment)
    Open3.capture3(environment, "bash", Rails.root.join("deploy/audit-leave-history.sh").to_s)
  end
end
