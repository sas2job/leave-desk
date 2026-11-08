require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  test "2027 demo calendar gives every employee approved annual and birthday leave" do
    original_time = Time.current
    load_development_seeds
    employees = demo_employees
    assert_equal 21, employees.size
    assert_equal original_time, Time.current
    assert FederalCalendar.exists?(year: 2027)

    employees.each do |employee|
      assert_not_nil employee.birthday_on
      requests = employee.leave_requests.where(starts_on: Date.new(2027, 1, 1)..Date.new(2027, 12, 31))
      assert_equal 3, requests.count
      assert_equal 2, requests.joins(:leave_type).where(leave_types: { code: "ANNUAL" }).count
      assert_equal 1, requests.joins(:leave_type).where(leave_types: { code: "BIRTHDAY" }).count
      assert requests.all?(&:approved?)
      assert requests.all?(&:full_calendar_days?)
      assert requests.all? { |request| request.reviewer_id == employee.manager_id && request.reviewed_at.present? }
      assert requests.all? { |request| request.events.order(:id).pluck(:event_type) == %w[created approved] }
      assert requests.select(&:annual_leave?).all? { |request| request.legal_review.present? }
    end

    birthday = employees.find_by!(email_address: "employee@leave-desk.test")
      .leave_requests.joins(:leave_type).find_by!(leave_types: { code: "BIRTHDAY" })
    assert_equal Date.new(2027, 1, 20), birthday.starts_on
    weekday_birthday = employees.find_by!(email_address: "employee2@leave-desk.test")
      .leave_requests.joins(:leave_type).find_by!(leave_types: { code: "BIRTHDAY" })
    assert_equal Date.new(2027, 2, 4), weekday_birthday.starts_on
  end

  test "2027 demo calendar has overlaps throughout the year" do
    load_development_seeds
    dates = (Date.new(2027, 1, 1)..Date.new(2027, 12, 31)).to_a
    rows = demo_employees.map do |employee|
      requests = employee.leave_requests.approved.where(starts_on: dates.first..dates.last)
      { employee:, leave_days: requests.flat_map { |request| (request.starts_on..request.ends_on).to_a }.to_set }
    end
    coverage = dates.index_with { |date| rows.count { |row| row[:leave_days].include?(date) } }
    report = TeamCalendarOverlapReport.new(rows:, coverage:, dates:)

    assert_equal (1..12).to_a, report.months.map { |month| month[:month] }
    assert_operator coverage.values.max, :>=, 4
    assert report.months.all? { |month| month[:ranges].any? { |range| range[:employees].size >= 2 } }
  end

  test "demo birthday dates respect transferred working and nonworking days" do
    load Rails.root.join("db/seeds.rb")
    manager = User.create!(name: "Seed Manager", email_address: "calendar-seed-manager@example.test",
      password: "test-password", role: :manager)
    employees = [ Date.new(1990, 1, 17), Date.new(1990, 2, 20), Date.new(1990, 11, 5) ].map.with_index do |birthday_on, index|
      User.create!(name: "Seed Employee", email_address: "calendar-seed-#{index}@example.test",
        password: "test-password", manager:, birthday_on:)
    end
    require Rails.root.join("db/seeds/development_calendar")
    DevelopmentCalendarSeed.new(year: 2027, employees:).call

    assert_equal [ Date.new(2027, 1, 20), Date.new(2027, 2, 20), Date.new(2027, 11, 10) ],
      employees.map { |employee| employee.leave_requests.joins(:leave_type).find_by!(leave_types: { code: "BIRTHDAY" }).starts_on }
  end

  test "rerunning demo calendar preserves birthdays requests and their history" do
    load_development_seeds
    employee = User.find_by!(email_address: "employee1@leave-desk.test")
    employee.update!(birthday_on: Date.new(1988, 6, 15))
    requests = LeaveRequest.order(:id).pluck(:id, :status, :starts_on, :ends_on, :reviewer_id, :reviewed_at)
    events = LeaveRequestEvent.count
    reviews = LeaveLegalReview.count
    notifications = Notification.count

    load_development_seeds

    assert_equal Date.new(1988, 6, 15), employee.reload.birthday_on
    assert_equal requests, LeaveRequest.order(:id).pluck(:id, :status, :starts_on, :ends_on, :reviewer_id, :reviewed_at)
    assert_equal events, LeaveRequestEvent.count
    assert_equal reviews, LeaveLegalReview.count
    assert_equal notifications, Notification.count
  end

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

    expected_codes = %w[ANNUAL BIRTHDAY CHILDCARE MATERNITY SICK UNPAID]
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

  private

  def load_development_seeds
    load Rails.root.join("db/seeds.rb")
    load Rails.root.join("db/seeds/development.rb")
  end

  def demo_employees
    addresses = [ "employee@leave-desk.test", *(1..20).map { |index| "employee#{index}@leave-desk.test" } ]
    User.where(email_address: addresses)
  end
end
