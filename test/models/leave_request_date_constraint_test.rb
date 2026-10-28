require "test_helper"

class LeaveRequestDateConstraintTest < ActiveSupport::TestCase
  setup do
    employee = User.create!(name: "Employee", email_address: "employee@example.test",
                            password: "test-password")
    leave_type = LeaveType.create!(name: "Annual leave", code: "test_annual")
    @request = LeaveRequest.create!(employee:, leave_type:,
                                    starts_on: Date.new(2026, 10, 14),
                                    ends_on: Date.new(2026, 10, 15))
  end

  test "database rejects non-finite start date with its own constraint" do
    assert_date_constraint("leave_requests_supported_start_date") do
      change_date(starts_on: Arel.sql("'-infinity'::date"))
    end
  end

  test "database rejects non-finite end date with its own constraint" do
    assert_date_constraint("leave_requests_supported_end_date") do
      change_date(ends_on: Arel.sql("'infinity'::date"))
    end
  end

  test "database rejects finite start date below supported range" do
    assert_date_constraint("leave_requests_supported_start_date") do
      change_date(starts_on: Date.new(1999, 12, 31))
    end
  end

  test "database rejects finite end date above supported range" do
    assert_date_constraint("leave_requests_supported_end_date") do
      change_date(ends_on: Date.new(2101, 1, 1))
    end
  end

  test "start-date assertion fails when its guard is missing on an isolated copy" do
    assert_guard_is_necessary("leave_requests_supported_start_date") do
      change_date(starts_on: Arel.sql("'-infinity'::date"))
    end
  end

  test "end-date assertion fails when its guard is missing on an isolated copy" do
    assert_guard_is_necessary("leave_requests_supported_end_date") do
      change_date(ends_on: Arel.sql("'infinity'::date"))
    end
  end

  private

  def assert_guard_is_necessary(name, &block)
    connection = ActiveRecord::Base.connection
    connection.execute("CREATE TEMP TABLE leave_requests (LIKE public.leave_requests INCLUDING ALL)")
    connection.execute("INSERT INTO pg_temp.leave_requests " \
                       "SELECT * FROM public.leave_requests WHERE id = #{@request.id}")
    connection.execute("ALTER TABLE pg_temp.leave_requests DROP CONSTRAINT #{name}")

    assert_raises(Minitest::Assertion) do
      assert_date_constraint(name, &block)
    end
  end

  def change_date(attributes)
    LeaveRequest.where(id: @request.id).update_all(attributes)
  end

  def assert_date_constraint(name)
    error = assert_raises(ActiveRecord::CheckViolation) do
      LeaveRequest.transaction(requires_new: true) { yield }
    end
    assert_equal name, error.cause.result.error_field(PG::Result::PG_DIAG_CONSTRAINT_NAME)
  end
end
