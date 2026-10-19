require "test_helper"
require "stringio"

class FederalCalendarImporterRawDateTest < ActiveSupport::TestCase
  INVALID_DATES = [ "infinity", "-infinity", "2026-02-30", "2026-1-01" ].freeze

  test "rejects raw holiday dates before PostgreSQL array coercion" do
    INVALID_DATES.each do |value|
      error = assert_raises(FederalCalendarImporter::InvalidFile) do
        FederalCalendarImporter.call(StringIO.new(calendar_json(public_holiday: value)))
      end

      assert_equal "Праздничные даты должны быть в формате ГГГГ-ММ-ДД", error.message
    end
    assert_empty FederalCalendar.where(year: 2026)
  end

  test "rejects raw transfer dates before calendar assignment" do
    error = assert_raises(FederalCalendarImporter::InvalidFile) do
      FederalCalendarImporter.call(StringIO.new(calendar_json(transfer_from: "infinity")))
    end

    assert_equal "Даты переносов должны быть в формате ГГГГ-ММ-ДД", error.message
    assert_empty FederalCalendar.where(year: 2026)
  end

  test "failed replacement does not change requests events or notifications" do
    calendar = FederalCalendarImporter.call(StringIO.new(calendar_json))
    manager = User.create!(name: "Manager", email_address: "raw-date-manager@example.test",
      password: "test-password", role: :manager)
    employee = User.create!(name: "Employee", email_address: "raw-date-employee@example.test",
      password: "test-password", manager:)
    leave_type = LeaveType.create!(name: "Annual leave", code: "RAW_DATE_ANNUAL",
      holiday_handling: :exclude_public_holidays)
    request = LeaveRequest.create!(employee:, leave_type:,
      starts_on: Date.new(2026, 6, 11), ends_on: Date.new(2026, 6, 13))
    baseline = [ calendar.attributes, request.attributes, LeaveRequestEvent.count, Notification.count ]

    INVALID_DATES.each do |value|
      assert_raises(FederalCalendarImporter::InvalidFile) do
        FederalCalendarImporter.call(StringIO.new(calendar_json(public_holiday: value)), replace: true)
      end
    end

    assert_equal baseline,
      [ calendar.reload.attributes, request.reload.attributes, LeaveRequestEvent.count, Notification.count ]
  end

  test "calendar validation handles unexpected typed holiday values" do
    calendar = FederalCalendar.new(year: 2026, legal_basis: "НПА",
      public_holidays: [ "infinity" ])

    assert_not calendar.valid?
    assert_includes calendar.errors[:public_holidays], "содержат неверную дату"
  end

  private

  def calendar_json(public_holiday: "2026-01-01", transfer_from: "2026-03-07")
    {
      year: 2026,
      legal_basis: "НПА",
      public_holidays: [ public_holiday ],
      transfers: [ { from: transfer_from, to: "2026-03-09" } ]
    }.to_json
  end
end
