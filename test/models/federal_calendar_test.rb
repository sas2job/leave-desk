require "test_helper"

class FederalCalendarTest < ActiveSupport::TestCase
  test "calendar separates holidays from transferred days off" do
    calendar = FederalCalendar.create!(year: 2026, legal_basis: "Статья 112 ТК РФ; постановление о переносах",
      public_holidays: RussianFederalHoliday.fixed_dates_for(2026),
      transfers: [ { "from" => "2026-03-07", "to" => "2026-03-09" } ])

    assert calendar.public_holiday?(Date.new(2026, 3, 8))
    assert calendar.day_off?(Date.new(2026, 3, 8))
    assert_not calendar.public_holiday?(Date.new(2026, 3, 9))
    assert calendar.day_off?(Date.new(2026, 3, 9))
    assert_not calendar.day_off?(Date.new(2026, 3, 7))
  end

  test "rejects malformed and out of year dates" do
    calendar = FederalCalendar.new(year: 2026, legal_basis: "НПА")
    calendar.public_holidays_input = "2026-01-01\n2027-01-02"
    calendar.transfers_input = "2026-03-07 -> 2027-03-09"

    assert_not calendar.valid?
    assert_predicate calendar.errors[:public_holidays], :present?
    assert_predicate calendar.errors[:transfers], :present?
  end

  test "rejects duplicate dates and transfer to holiday" do
    calendar = FederalCalendar.new(year: 2026, legal_basis: "НПА")
    calendar.public_holidays_input = "2026-01-01\n2026-01-01"
    calendar.transfers_input = "2026-03-07 -> 2026-01-01"

    assert_not calendar.valid?
    assert_includes calendar.errors[:public_holidays], "не могут повторяться"
    assert_not_includes calendar.errors[:transfers], "не могут переносить выходной на праздник"

    calendar.public_holidays_input = "2026-01-01"
    assert_not calendar.valid?
    assert_includes calendar.errors[:transfers], "не могут переносить выходной на праздник"
  end

  test "rejects oversized form collections before parsing dates" do
    calendar = FederalCalendar.new(year: 2026, legal_basis: "НПА")
    calendar.public_holidays_input = "2026-01-01\n" * 10_000
    calendar.transfers_input = "2026-02-01 -> 2026-02-02\n" * 10_000

    assert_not calendar.valid?
    assert_includes calendar.errors[:public_holidays_input], "не могут содержать более 366 строк"
    assert_includes calendar.errors[:transfers_input], "не могут содержать более 366 строк"
    assert_empty calendar.public_holidays
    assert_empty calendar.transfers
  end

  test "rejects oversized arrays before normalizing dates" do
    calendar = FederalCalendar.new(year: 2026, legal_basis: "НПА",
      public_holidays: [ "2026-01-01" ] * 367,
      transfers: [ { "from" => "2026-02-01", "to" => "2026-02-02" } ] * 367)

    assert_not calendar.valid?
    assert_includes calendar.errors[:public_holidays], "не могут содержать более 366 дат"
    assert_includes calendar.errors[:transfers], "не могут содержать более 366 переносов"
  end
end
