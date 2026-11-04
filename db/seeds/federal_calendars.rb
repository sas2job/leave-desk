# https://static.government.ru/media/files/4jeB8hNKm69ggOa9yDiYOli6YoAyM21i.pdf
# https://www.mintrans.gov.ru/eye/press-center/branch-news/9491
federal_years = {
  2026 => {
    legal_basis: "Статья 112 ТК РФ; Постановление Правительства РФ от 24.09.2025 № 1466",
    transfers: [
      { "from" => "2026-01-03", "to" => "2026-01-09" },
      { "from" => "2026-01-04", "to" => "2026-12-31" }
    ]
  },
  2027 => {
    legal_basis: "Статья 112 ТК РФ; Постановление Правительства РФ от 17.09.2026 № 1187",
    transfers: [
      { "from" => "2027-01-02", "to" => "2027-11-05" },
      { "from" => "2027-01-03", "to" => "2027-12-31" },
      { "from" => "2027-02-20", "to" => "2027-02-22" }
    ]
  }
}

federal_years.each do |year, attributes|
  calendar = FederalCalendar.find_or_initialize_by(year:)
  next if calendar.persisted?

  calendar.assign_attributes(attributes.merge(public_holidays: RussianFederalHoliday.fixed_dates_for(year)))
  calendar.save!
end
