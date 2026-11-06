class TeamCalendarOverlapReport
  attr_reader :months, :employee_count, :overlap_days, :dates, :generated_at

  def initialize(rows:, coverage:, dates:)
    @dates = dates
    @employee_count = rows.size
    @generated_at = Time.current
    @months = dates.group_by(&:month).filter_map do |month, month_dates|
      overlapping = month_dates.select { |date| coverage.fetch(date) >= 2 }
      next if overlapping.empty?

      ranges = overlapping.each_with_object([]) do |date, result|
        employees = rows.select { |row| row[:leave_days].include?(date) }.map { |row| row[:employee] }
        previous = result.last
        if previous && previous[:ends_on] + 1 == date && previous[:employees].map(&:id) == employees.map(&:id)
          previous[:ends_on] = date
        else
          result << { starts_on: date, ends_on: date, employees: }
        end
      end
      { month:, overlap_days: overlapping.size, ranges: }
    end
    @overlap_days = months.sum { |month| month[:overlap_days] }
  end

  def month_label(month)
    I18n.l(Date.new(dates.first.year, month[:month], 1), format: "%B %Y")
  end

  def to_markdown
    lines = [ "# Пересечения отпусков — #{dates.first.year}", "",
      "Сформировано: #{generated_at.strftime('%d.%m.%Y %H:%M %Z')}.",
      "Период: #{date_label(dates.first)}–#{date_label(dates.last)}.",
      "Сотрудников: #{employee_count} · Дней с пересечениями: #{overlap_days}.", "",
      "Учитываются одобренные отсутствия и использованные части после отзыва или выхода. " \
        "День с пересечением означает двух и более отсутствующих в течение дня; " \
        "это не обязательно одновременное отсутствие в одни часы.", "" ]
    if months.empty?
      lines << "В выбранном периоде пересечений нет."
    else
      months.each do |month|
        lines.concat([ "## #{month_label(month)}", "", "Дней с пересечениями: #{month[:overlap_days]}.", "",
          "| Период | Отсутствуют | Сотрудники |", "| --- | ---: | --- |" ])
        month[:ranges].each do |range|
          period = "#{date_label(range[:starts_on])}–#{date_label(range[:ends_on])}"
          names = range[:employees].map { |employee| escape_cell(employee.name) }.join(", ")
          lines << "| #{period} | #{range[:employees].size} | #{names} |"
        end
        lines << ""
      end
    end
    lines.join("\n") + "\n"
  end

  private

  def date_label(date)
    date.strftime("%d.%m.%Y")
  end

  def escape_cell(value)
    value.gsub(/[\r\n]+/, " ").gsub(/[\\`*_\[\]<>|]/) { |character| "\\#{character}" }
  end
end
