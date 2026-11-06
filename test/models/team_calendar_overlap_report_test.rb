require "test_helper"

class TeamCalendarOverlapReportTest < ActiveSupport::TestCase
  test "report omits empty months groups equal participants and preserves calendar total" do
    first = User.new(id: 1, name: "Person | one")
    second = User.new(id: 2, name: "Person <two>")
    third = User.new(id: 3, name: "Person three")
    january = Date.new(2026, 1, 10)..Date.new(2026, 1, 12)
    march = Date.new(2026, 3, 1)
    rows = [ { employee: first, leave_days: (january.to_a + [ march ]).to_set },
      { employee: second, leave_days: january.to_set }, { employee: third, leave_days: [ march ].to_set } ]
    dates = Date.new(2026, 1, 1).all_year.to_a
    coverage = dates.index_with { |date| rows.count { |row| row[:leave_days].include?(date) } }
    report = TeamCalendarOverlapReport.new(rows:, coverage:, dates:)

    assert_equal 4, report.overlap_days
    assert_equal [ 1, 3 ], report.months.map { |month| month[:month] }
    assert_equal 1, report.months.first[:ranges].size
    document = report.to_markdown
    assert_includes document, "10.01.2026–12.01.2026"
    assert_includes document, "Дней с пересечениями: 4"
    assert_includes document, "Person \\| one"
    assert_includes document, "Person \\<two\\>"
    assert_not_includes document, "февраль"
  end
end
