class RegionalCalendar < ApplicationRecord
  MAX_DATE_ENTRIES = FederalCalendar::MAX_DATE_ENTRIES
  MAX_INPUT_BYTES = 8 * 1024

  belongs_to :region
  validates :year, numericality: { only_integer: true, in: SupportedCalendarPeriod::YEARS },
    uniqueness: { scope: :region_id }
  validates :legal_basis, presence: true, length: { maximum: 1_000 }
  validates :complete, inclusion: { in: [ true, false ] }
  validate :year_has_valid_syntax
  validate :year_is_unchanged, on: :update
  validate :parse_form_dates
  validate :calendar_dates_are_valid
  after_update :flag_requests_with_changed_duration,
    if: -> { saved_change_to_public_holidays? || saved_change_to_complete? }

  def save(**options)
    with_calendar_lock { super }
  end

  def save!(**options)
    with_calendar_lock { super }
  end

  def public_holidays_input
    @public_holidays_input ||= public_holidays.map(&:iso8601).join("\n")
  end

  def public_holidays_input=(value)
    @public_holidays_input = value
  end

  def additional_days_off_input
    @additional_days_off_input ||= additional_days_off.map(&:iso8601).join("\n")
  end

  def additional_days_off_input=(value)
    @additional_days_off_input = value
  end

  def day_off?(date)
    public_holidays.include?(date) || additional_days_off.include?(date)
  end

  private

  def with_calendar_lock
    return yield unless region_id && SupportedCalendarPeriod::YEARS.cover?(year)

    FederalCalendar.with_year_lock(year) do
      Region.where(id: region_id).lock("FOR UPDATE").first
      yield
    end
  end

  def flag_requests_with_changed_duration
    year_dates = Date.new(year, 1, 1)..Date.new(year, 12, 31)
    LeaveRequest.where(region_id:, status: %i[pending approved], calendar_unverified: false)
      .where("starts_on <= ? AND ends_on >= ?", year_dates.end, year_dates.begin)
      .includes(:leave_type).find_each do |request|
      unless complete?
        request.flag_calendar_for_review!
        next
      end

      new_duration = request.precise_time? ? request.calendar_duration_in_minutes :
        (request.calendar_duration_in_days * 2).to_i
      saved_duration = request.precise_time? ? request.duration_minutes : request.duration_half_days
      request.flag_calendar_for_review! if new_duration != saved_duration
    end
  end

  def year_is_unchanged
    errors.add(:year, "нельзя изменить после создания календаря") if will_save_change_to_year?
    errors.add(:region, "нельзя изменить после создания календаря") if will_save_change_to_region_id?
  end

  def year_has_valid_syntax
    raw_year = attribute_before_type_cast("year")
    return if raw_year.is_a?(Integer)
    return if raw_year.is_a?(String) && raw_year.match?(/\A\d{4}\z/)

    errors.add(:year, "должен быть записан четырьмя цифрами")
  end

  def parse_form_dates
    { public_holidays: @public_holidays_input, additional_days_off: @additional_days_off_input }.each do |field, input|
      next unless instance_variable_defined?("@#{field}_input")

      unless input.is_a?(String)
        errors.add("#{field}_input", "должны содержать текст")
        next
      end

      unless input.valid_encoding?
        errors.add("#{field}_input", "должны содержать корректный текст")
        next
      end
      if input.bytesize > MAX_INPUT_BYTES
        errors.add("#{field}_input", "не могут превышать 8 КиБ")
        next
      end
      if input.each_line.take(MAX_DATE_ENTRIES + 1).size > MAX_DATE_ENTRIES
        errors.add("#{field}_input", "не могут содержать более #{MAX_DATE_ENTRIES} строк")
        next
      end
      dates = input.lines.filter_map do |line|
        value = line.strip
        next if value.empty?

        date = FederalCalendar.parse_iso_date(value)
        errors.add("#{field}_input", "должны быть в формате ГГГГ-ММ-ДД") unless date
        date
      end
      public_send("#{field}=", dates)
    end
  end

  def calendar_dates_are_valid
    %i[public_holidays additional_days_off].each do |field|
      dates = public_send(field)
      next if errors["#{field}_input"].any?

      errors.add(field, "не могут содержать более #{MAX_DATE_ENTRIES} дат") if dates.size > MAX_DATE_ENTRIES
      errors.add(field, "не могут повторяться") if dates.uniq.size != dates.size
      errors.add(field, "должны относиться к году календаря") if dates.any? { |date| !date.is_a?(Date) || date.year != year }
    end
    if (public_holidays & additional_days_off).any?
      errors.add(:additional_days_off, "не должны совпадать с праздничными датами")
    end
  end
end
