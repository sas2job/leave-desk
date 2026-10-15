class FederalCalendar < ApplicationRecord
  DATE_PATTERN = /\A\d{4}-\d{2}-\d{2}\z/

  def self.nonworking_dates(dates)
    return Set.new if dates.empty?

    calendar = find_by(year: dates.first.year)
    dates.select do |date|
      calendar ? calendar.day_off?(date) :
        date.saturday? || date.sunday? || RussianFederalHoliday::FIXED_DATES.include?([ date.month, date.day ])
    end.to_set
  end

  validates :year, numericality: { only_integer: true, in: SupportedCalendarPeriod::YEARS }, uniqueness: true
  validates :legal_basis, presence: true
  validates :legal_basis, length: { maximum: 1_000 }, if: :will_save_change_to_legal_basis?
  validate :year_has_valid_syntax
  validate :year_is_unchanged, on: :update
  validate :parse_form_dates
  validate :calendar_dates_are_valid
  after_update :flag_requests_with_changed_duration, if: :saved_change_to_public_holidays?

  def public_holidays_input
    @public_holidays_input ||= public_holidays.map(&:iso8601).join("\n")
  end

  def public_holidays_input=(value)
    @public_holidays_input = value
  end

  def transfers_input
    @transfers_input ||= transfers.map { |pair| "#{pair.fetch('from')} -> #{pair.fetch('to')}" }.join("\n")
  end

  def transfers_input=(value)
    @transfers_input = value
  end

  def public_holiday?(date)
    public_holidays.include?(date)
  end

  def day_off?(date)
    return true if public_holiday?(date)
    return true if transfers.any? { |pair| pair.fetch("to") == date.iso8601 }
    return false if transfers.any? { |pair| pair.fetch("from") == date.iso8601 }

    date.saturday? || date.sunday?
  end

  private

  def flag_requests_with_changed_duration
    year_dates = Date.new(year, 1, 1)..Date.new(year, 12, 31)
    LeaveRequest.where(starts_on: year_dates, status: %i[pending approved], calendar_unverified: false)
      .includes(:leave_type).find_each do |request|
      next if (request.calendar_duration_in_days * 2).to_i == request.duration_half_days

      request.flag_calendar_for_review!
    end
  end

  def year_has_valid_syntax
    raw_year = attribute_before_type_cast("year")
    return if raw_year.is_a?(Integer)
    return if raw_year.is_a?(String) && raw_year.match?(/\A\d{4}\z/)

    errors.add(:year, "должен быть записан четырьмя цифрами")
  end

  def year_is_unchanged
    errors.add(:year, "нельзя изменить после создания календаря") if will_save_change_to_year?
  end

  def parse_form_dates
    if instance_variable_defined?(:@public_holidays_input)
      self.public_holidays = parse_date_lines(@public_holidays_input, :public_holidays)
    end
    return unless instance_variable_defined?(:@transfers_input)

    self.transfers = @transfers_input.to_s.lines.filter_map do |line|
      text = line.strip
      next if text.empty?

      parts = text.split(/\s*(?:->|→)\s*/, -1)
      from, to = parts
      if parts.size == 2 && date_from_input(from) && date_from_input(to)
        { "from" => from, "to" => to }
      else
        errors.add(:transfers_input, "должны быть в формате ГГГГ-ММ-ДД -> ГГГГ-ММ-ДД")
        nil
      end
    end
  end

  def parse_date_lines(input, field)
    input.to_s.lines.filter_map do |line|
      text = line.strip
      next if text.empty?

      date = date_from_input(text)
      errors.add(field, "должны быть в формате ГГГГ-ММ-ДД") unless date
      date
    end
  end

  def date_from_input(text)
    return unless text&.match?(DATE_PATTERN)

    Date.iso8601(text)
  rescue Date::Error
    nil
  end

  def calendar_dates_are_valid
    holidays = public_holidays.filter_map { |value| normalize_date(value, :public_holidays) }
    errors.add(:public_holidays, "должны быть указаны") if holidays.empty?
    errors.add(:public_holidays, "не могут повторяться") if holidays.uniq.size != holidays.size
    errors.add(:public_holidays, "должны относиться к выбранному году") if holidays.any? { |date| date.year != year }

    pairs = transfers.filter_map do |pair|
      unless pair.is_a?(Hash) && pair.keys.sort == %w[from to]
        errors.add(:transfers, "содержат неверную пару дат")
        next
      end
      from = normalize_date(pair["from"], :transfers)
      to = normalize_date(pair["to"], :transfers)
      [ from, to ] if from && to
    end
    errors.add(:transfers, "должны относиться к выбранному году") if pairs.flatten.any? { |date| date.year != year }
    errors.add(:transfers, "не могут переносить день на сам себя") if pairs.any? { |from, to| from == to }
    errors.add(:transfers, "не могут повторять исходные или новые даты") if pairs.map(&:first).uniq.size != pairs.size || pairs.map(&:last).uniq.size != pairs.size
    errors.add(:transfers, "не могут переносить выходной на праздник") if pairs.any? { |_from, to| holidays.include?(to) }
  end

  def normalize_date(value, field)
    date = value.is_a?(Date) ? value : date_from_input(value)
    errors.add(field, "содержат неверную дату") unless date
    date
  end
end
