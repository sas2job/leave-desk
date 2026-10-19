require "json"

class FederalCalendarImporter
  class InvalidFile < StandardError; end

  MAX_BYTES = 64 * 1024
  FIELDS = %w[year legal_basis public_holidays transfers].freeze

  def self.call(io, replace: false)
    content = io.read(MAX_BYTES + 1).to_s
    raise InvalidFile, "Файл календаря превышает 64 КиБ" if content.bytesize > MAX_BYTES

    data = JSON.parse(content)
    validate_structure!(data)
    data = normalize_dates!(data)

    FederalCalendar.transaction do
      calendar = FederalCalendar.lock("FOR UPDATE").find_by(year: data.fetch("year"))
      raise InvalidFile, "Календарь года уже существует; укажите замену явно" if calendar && !replace

      calendar ||= FederalCalendar.new(year: data.fetch("year"))
      calendar.assign_attributes(legal_basis: data.fetch("legal_basis"),
        public_holidays: data.fetch("public_holidays"), transfers: data.fetch("transfers"))
      calendar.save!
      calendar
    end
  rescue JSON::ParserError
    raise InvalidFile, "Файл не содержит корректный JSON"
  rescue ActiveRecord::RecordInvalid => error
    raise InvalidFile, error.record.errors.full_messages.join("; ")
  rescue ActiveRecord::RecordNotUnique
    raise InvalidFile, "Календарь года был изменён параллельно; повторите импорт"
  end

  def self.validate_structure!(data)
    unless data.is_a?(Hash) && data.keys.sort == FIELDS.sort
      raise InvalidFile, "Ожидаются поля: #{FIELDS.join(', ')}"
    end
    unless data["year"].is_a?(Integer) && data["legal_basis"].is_a?(String) &&
        data["public_holidays"].is_a?(Array) && data["public_holidays"].all? { |date| date.is_a?(String) } &&
        data["transfers"].is_a?(Array) && data["transfers"].all? { |pair| valid_pair?(pair) }
      raise InvalidFile, "Типы полей календаря или пар переноса неверны"
    end
  end

  def self.valid_pair?(pair)
    pair.is_a?(Hash) && pair.keys.sort == %w[from to] && pair.values.all? { |date| date.is_a?(String) }
  end

  def self.normalize_dates!(data)
    public_holidays = data.fetch("public_holidays").map do |value|
      parse_date!(value, "Праздничные даты")
    end
    transfers = data.fetch("transfers").map do |pair|
      {
        "from" => parse_date!(pair.fetch("from"), "Даты переносов").iso8601,
        "to" => parse_date!(pair.fetch("to"), "Даты переносов").iso8601
      }
    end
    data.merge("public_holidays" => public_holidays, "transfers" => transfers)
  end

  def self.parse_date!(value, field_name)
    FederalCalendar.parse_iso_date(value) ||
      raise(InvalidFile, "#{field_name} должны быть в формате ГГГГ-ММ-ДД")
  end

  private_class_method :validate_structure!, :valid_pair?, :normalize_dates!, :parse_date!
end
