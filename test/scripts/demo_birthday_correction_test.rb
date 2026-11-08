require "test_helper"
require Rails.root.join("script/correct_demo_birthdays")

class DemoBirthdayCorrectionTest < ActiveSupport::TestCase
  setup do
    load Rails.root.join("db/seeds.rb")
    @manager = User.create!(name: "Birthday Manager", email_address: "birthday-manager@leave-desk.test",
      password: "test-password", role: :manager)
    @users = 20.times.map do |index|
      User.create!(name: format("Demo %02d", index), email_address: "employee#{index + 1}@leave-desk.test",
        password: "test-password", manager: @manager,
        birthday_on: Date.new(1980 + index % 5, index % 12 + 1, index * 3 % 27 + 1))
    end
    @other = User.create!(name: "Other Employee", email_address: "other@example.test",
      password: "test-password", birthday_on: Date.new(1985, 11, 10))
    @correction = DemoBirthdayCorrection.new
  end

  test "preview breaks the calendar order pattern without writing profiles" do
    dates = @users.map { |user| [ user.id, user.birthday_on, user.updated_at ] }
    preview = @correction.preview

    assert_equal preview, @correction.preview
    assert_equal dates, @users.map { |user| user.reload.attributes.values_at("id", "birthday_on", "updated_at") }
    assert_operator preview[:before][:longest_increasing_run], :>=, 10
    assert_operator preview[:after][:longest_increasing_run], :<=, 6
    assert_operator preview[:after][:longest_decreasing_run], :<=, 6
    assert_operator preview[:changed_birthdays], :>=, 18
    assert_equal 0, preview[:after][:missing_birthdays]
  end

  test "apply preserves birth years other profile fields leave and repeat runs" do
    request = LeaveRequest.create!(employee: @users.first, leave_type: LeaveType.find_by!(code: "ANNUAL"),
      starts_on: Date.new(2026, 12, 1), ends_on: Date.new(2026, 12, 7))
    request.approve!(by: @manager, legal_review: { conditions_confirmed: true,
      working_year_starts_on: Date.new(2026, 1, 1), working_year_ends_on: Date.new(2026, 12, 31), entitlement_days: 28 })
    request_attributes = request.attributes
    counts = [ LeaveRequest.count, LeaveRequestEvent.count, Notification.count ]
    fields = @users.to_h { |user| [ user.id, user.attributes.except("birthday_on", "updated_at") ] }
    years = @users.to_h { |user| [ user.id, user.birthday_on.year ] }
    other_attributes = @other.attributes
    preview = @correction.preview
    result = @correction.apply!(expected_digest: preview.fetch(:plan_digest))

    assert result[:applied]
    assert_operator result[:actual_after][:longest_increasing_run], :<=, 6
    @users.each do |user|
      user.reload
      assert_equal years.fetch(user.id), user.birthday_on.year
      assert user.attributes.except("birthday_on", "updated_at") == fields.fetch(user.id), "Only birthday fields may change"
    end
    assert @other.reload.attributes == other_attributes
    assert_equal request_attributes, request.reload.attributes
    assert_equal counts, [ LeaveRequest.count, LeaveRequestEvent.count, Notification.count ]
    timestamps = @users.map(&:updated_at)
    assert @correction.preview[:already_applied]
    assert @correction.apply!(expected_digest: preview.fetch(:plan_digest))[:already_applied]
    assert_equal timestamps, @users.map { |user| user.reload.updated_at }
  end

  test "a stale birthday plan is rejected before further writes" do
    preview = @correction.preview
    @users.first.update!(birthday_on: Date.new(1980, 6, 15))
    dates = @users.map { |user| user.reload.birthday_on }

    assert_raises(DemoBirthdayCorrection::UnsafeData) { @correction.apply!(expected_digest: preview.fetch(:plan_digest)) }
    assert_equal dates, @users.map { |user| user.reload.birthday_on }
  end

  test "a missing selected account is rejected" do
    @users.last.update!(active: false)

    assert_raises(DemoBirthdayCorrection::UnsafeData) { @correction.preview }
  end
end
