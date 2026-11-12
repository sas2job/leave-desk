require "test_helper"
require Rails.root.join("script/reseed_staging_demo")

class ReseedStagingDemoTest < ActiveSupport::TestCase
  setup do
    load Rails.root.join("db/seeds.rb")
    @administrator = User.create!(name: "Demo Administrator", email_address: "reset-admin@leave-desk.test", password: "test-password", role: :administrator)
    @manager = User.create!(name: "Demo Manager", email_address: "reset-manager@leave-desk.test", password: "test-password", role: :manager)
    @employees = 4.times.map do |index|
      User.create!(name: "Demo Employee", email_address: "reset-#{index}@leave-desk.test", password: "test-password", manager: @manager,
        birthday_on: Date.new(1990, index + 2, 10 + index), city: index.even? ? "Москва" : "Минск")
    end
    @outside = User.create!(name: "Other Employee", email_address: "outside-reset@example.test", password: "test-password", manager: @manager)
    type = LeaveType.find_by!(code: "SICK")
    @original = LeaveRequest.create!(employee: @employees.first, leave_type: type, starts_on: Date.new(2026, 10, 1), ends_on: Date.new(2026, 10, 3))
    @original.approve!(by: @manager)
    @outside_request = LeaveRequest.create!(employee: @outside, leave_type: type, starts_on: Date.new(2026, 10, 4), ends_on: Date.new(2026, 10, 6))
    @session = @employees.first.sessions.create!(ip_address: "127.0.0.1", user_agent: "Reset test")
    @reseed = StagingDemoReseed.new
  end

  test "preview is repeatable and rolls back all seed and profile changes" do
    before = snapshot
    first = @reseed.preview
    assert_equal first, @reseed.preview
    assert_equal before, snapshot
    assert first[:passwords_unchanged]
    assert first[:sessions_unchanged]
    assert first[:calendars_unchanged]
    assert_equal 28, first[:after][:requests]
    assert_equal 18, first[:after][:working_years]
    assert_equal 0, DemoSeedArchive.count
  end

  test "apply archives old activity preserves passwords and recreates valid budgets" do
    identities = User.order(:id).pluck(:id, :password_digest)
    outside = @outside_request.attributes
    old_event_ids = @original.events.pluck(:id)
    preview = @reseed.preview
    applied = @reseed.apply!(expected_digest: preview[:plan_digest])
    assert applied[:passwords_unchanged]
    assert identities == User.order(:id).pluck(:id, :password_digest), "Passwords must remain identical"
    assert Session.exists?(@session.id)
    assert_equal outside, @outside_request.reload.attributes
    archive = DemoSeedArchive.sole
    assert_equal preview[:plan_digest], archive.plan_digest
    assert archive.archived_data.fetch("leave_requests").any? { |request| request.fetch("id") == @original.id }
    assert old_event_ids.all? { |id| archive.archived_data.fetch("leave_request_events").any? { |event| event.fetch("id") == id } }
    assert_not archive.archived_data.key?("users")
    assert_not LeaveRequest.exists?(@original.id)
    assert_equal [ 28, 30, 31, 33 ], @employees.map { |employee| employee.reload.annual_default_days }.sort
    assert_equal 28, applied[:after][:requests]
    assert_equal 18, applied[:after][:working_years]
    assert_operator applied[:after][:minimum_current_available_days], :>, 0
    assert_operator applied[:after][:maximum_current_available_days], :<, 50
    assert_not archive.destroy
  end

  test "a stale digest stops before replacing activity" do
    digest = @reseed.preview[:plan_digest]
    @original.update!(employee_comment: "Изменение после предварительного просмотра")
    before = snapshot
    assert_raises(StagingDemoReseed::UnsafeData) { @reseed.apply!(expected_digest: digest) }
    assert_equal before, snapshot
    assert_equal 0, DemoSeedArchive.count
  end

  test "a failure during generation restores all original rows" do
    before = snapshot
    generator = Object.new
    generator.define_singleton_method(:call) { |users:| raise "Injected generation failure" }
    assert_raises(RuntimeError) { StagingDemoReseed.new(scenarios: generator).preview }
    assert_equal before, snapshot
  end

  test "missing required calendar stops before any write" do
    FederalCalendar.where(year: 2027).delete_all
    before = snapshot
    assert_raises(StagingDemoReseed::UnsafeData) { @reseed.preview }
    assert_equal before, snapshot
  end

  private

  def snapshot
    [ User.order(:id).map(&:attributes), LeaveRequest.order(:id).map(&:attributes), LeaveRequestEvent.order(:id).map(&:attributes),
      Notification.order(:id).map(&:attributes), AnnualLeaveYear.order(:id).map(&:attributes), AnnualLeaveBooking.order(:id).map(&:attributes),
      DemoSeedArchive.order(:id).map(&:attributes), Session.order(:id).map(&:attributes) ]
  end
end
