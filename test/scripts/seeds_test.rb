require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  test "creates reference leave types idempotently" do
    2.times { load Rails.root.join("db/seeds.rb") }

    expected_codes = %w[ANNUAL BIRTHDAY SICK UNPAID]
    assert_equal expected_codes, LeaveType.where(code: expected_codes).order(:code).pluck(:code)
    assert_predicate LeaveType.find_by!(code: "ANNUAL"), :exclude_public_holidays?
    assert_predicate LeaveType.find_by!(code: "BIRTHDAY"), :include_public_holidays?
    assert_predicate LeaveType.find_by!(code: "SICK"), :include_public_holidays?
    assert_predicate LeaveType.find_by!(code: "UNPAID"), :include_public_holidays?
  end

  test "rerun preserves an administrator-disabled reference type" do
    load Rails.root.join("db/seeds.rb")
    leave_type = LeaveType.find_by!(code: "BIRTHDAY")
    leave_type.update!(active: false)

    load Rails.root.join("db/seeds.rb")

    assert_not leave_type.reload.active?
  end
end
