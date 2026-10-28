require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  test "development demo cities keep administrator changes on rerun" do
    load Rails.root.join("db/seeds.rb")
    load Rails.root.join("db/seeds/development.rb")

      assert_equal [ "Москва", "Europe/Moscow" ],
        User.find_by!(email_address: "employee1@leave-desk.test").attributes.values_at("city", "time_zone")
      assert_equal [ "Минск", "Europe/Minsk" ],
        User.find_by!(email_address: "employee2@leave-desk.test").attributes.values_at("city", "time_zone")
      bratsk = User.find_by!(email_address: "employee3@leave-desk.test")
      assert_equal [ "Братск", "Asia/Irkutsk" ], bratsk.attributes.values_at("city", "time_zone")

      bratsk.update!(city: "Омск", time_zone: "Asia/Omsk")
      load Rails.root.join("db/seeds/development.rb")
      assert_equal [ "Омск", "Asia/Omsk" ], bratsk.reload.attributes.values_at("city", "time_zone")
  end

  test "creates reference leave types idempotently" do
    2.times { load Rails.root.join("db/seeds.rb") }

    expected_codes = %w[ANNUAL BIRTHDAY SICK UNPAID]
    assert_equal expected_codes, LeaveType.where(code: expected_codes).order(:code).pluck(:code)
    assert_predicate LeaveType.find_by!(code: "ANNUAL"), :exclude_public_holidays?
    assert_predicate LeaveType.find_by!(code: "BIRTHDAY"), :include_public_holidays?
    assert_predicate LeaveType.find_by!(code: "SICK"), :include_public_holidays?
    assert_predicate LeaveType.find_by!(code: "UNPAID"), :include_public_holidays?
  end

  test "rerun preserves administrator edits after a request uses the policy" do
    load Rails.root.join("db/seeds.rb")
    annual = LeaveType.find_by!(code: "ANNUAL")
    annual.update!(name: "Переименованный отпуск", active: false)
    sick = LeaveType.find_by!(code: "SICK")
    sick.update!(holiday_handling: :exclude_public_holidays)
    employee = User.create!(name: "Example Employee", email_address: "seed-employee@example.test",
      password: "test-password")
    LeaveRequest.create!(employee:, leave_type: sick, starts_on: Date.current,
      ends_on: Date.current)

    2.times { load Rails.root.join("db/seeds.rb") }

    assert_equal "Переименованный отпуск", annual.reload.name
    assert_not annual.active?
    assert_predicate sick.reload, :exclude_public_holidays?
  end

  test "rerun preserves an administrator-disabled reference type" do
    load Rails.root.join("db/seeds.rb")
    leave_type = LeaveType.find_by!(code: "BIRTHDAY")
    leave_type.update!(active: false)

    load Rails.root.join("db/seeds.rb")

    assert_not leave_type.reload.active?
  end

  test "rerun does not duplicate birthday type after rejected code edit" do
    load Rails.root.join("db/seeds.rb")
    birthday_type = LeaveType.find_by!(code: "BIRTHDAY")

    assert_not birthday_type.update(code: "BDAY")

    load Rails.root.join("db/seeds.rb")

    assert_equal [ birthday_type.id ], LeaveType.where(code: "BIRTHDAY").pluck(:id)
    assert_not LeaveType.exists?(code: "BDAY")
  end
end
