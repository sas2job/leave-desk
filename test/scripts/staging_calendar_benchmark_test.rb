require "test_helper"
require Rails.root.join("script/benchmark_staging_calendar_2027")

class StagingCalendarBenchmarkTest < ActiveSupport::TestCase
  test "staging render checks use a temporary team and roll back all records" do
    load Rails.root.join("db/seeds.rb")
    counts = [ User.count, LeaveRequest.count, LeaveRequestEvent.count, Notification.count, LeaveLegalReview.count, Session.count ]
    result = StagingCalendarBenchmark2027.new(employee_count: 12).call

    assert_equal 12, result[:year][:employee_rows]
    assert_equal 365, result[:year][:day_columns]
    assert_equal 12, result[:month][:employee_rows]
    assert_equal 31, result[:month][:day_columns]
    assert_equal 3, result[:selected_overlap][:employee_rows]
    assert result[:rollback_verified]
    assert_equal counts, [ User.count, LeaveRequest.count, LeaveRequestEvent.count, Notification.count, LeaveLegalReview.count, Session.count ]
    assert_nil Current.session
  end
end
