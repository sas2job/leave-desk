require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  test "creates reference leave types idempotently" do
    2.times { load Rails.root.join("db/seeds.rb") }

    assert_equal %w[ANNUAL SICK UNPAID], LeaveType.order(:code).pluck(:code)
    assert_equal 3, LeaveType.where(code: %w[ANNUAL SICK UNPAID]).count
    assert_predicate LeaveType.find_by!(code: "ANNUAL"), :exclude_public_holidays?
    assert_predicate LeaveType.find_by!(code: "SICK"), :include_public_holidays?
    assert_predicate LeaveType.find_by!(code: "UNPAID"), :include_public_holidays?
  end
end
