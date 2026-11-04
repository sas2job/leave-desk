# Даты берутся из региональных НПА. Неполный год нельзя подтверждать для расчёта
# сохранённой длительности до публикации всех подвижных дат.
# Предварительный перечень регионов для проверки НПА:
# https://www.consultant.ru/document/cons_doc_LAW_311098/
candidate_regions = {
  "RU-AD" => "Республика Адыгея",
  "RU-AL" => "Республика Алтай",
  "RU-BA" => "Республика Башкортостан",
  "RU-BU" => "Республика Бурятия",
  "RU-DA" => "Республика Дагестан",
  "RU-IN" => "Республика Ингушетия",
  "RU-KB" => "Кабардино-Балкарская Республика",
  "RU-KL" => "Республика Калмыкия",
  "RU-KC" => "Карачаево-Черкесская Республика",
  "RU-KO" => "Республика Коми",
  "RU-CR" => "Республика Крым",
  "RU-MO" => "Республика Мордовия",
  "RU-SA" => "Республика Саха (Якутия)",
  "RU-SE" => "Республика Северная Осетия — Алания",
  "RU-TA" => "Республика Татарстан",
  "RU-TY" => "Республика Тыва",
  "RU-CE" => "Чеченская Республика",
  "RU-CU" => "Чувашская Республика",
  "RU-ZAB" => "Забайкальский край",
  "RU-KDA" => "Краснодарский край",
  "RU-STA" => "Ставропольский край",
  "RU-BEL" => "Белгородская область",
  "RU-BRY" => "Брянская область",
  "RU-IRK" => "Иркутская область",
  "RU-OMS" => "Омская область",
  "RU-PNZ" => "Пензенская область",
  "RU-SAR" => "Саратовская область",
  "RU-SEV" => "Севастополь"
}
candidate_regions.each do |code, name|
  Region.find_or_create_by!(code:) { |region| region.name = name }
end

regions = [
  # https://npa.bashkortostan.ru/46673/ (2026)
  # https://npa.bashkortostan.ru/49841/ (2027)
  {
    code: "RU-BA", name: "Республика Башкортостан",
    calendars: [
      {
        year: 2026, complete: false,
        legal_basis: "Постановление Правительства РБ от 15.07.2025 № 322; остальные региональные даты требуют проверки",
        public_holidays: %w[2026-03-20 2026-05-27]
      },
      {
        year: 2027, complete: false,
        legal_basis: "Постановление Правительства РБ от 16.06.2026 № 205; остальные региональные даты требуют проверки",
        public_holidays: %w[2027-03-09 2027-05-16]
      }
    ]
  },
  # https://admkrai.krasnodar.ru/content/1291/?doc_numb=4909-%D0%9A%D0%97
  # https://admkrai.krasnodar.ru/upload/iblock/2f1/w06duspt9iqykhwjdpy413njlc9yzfww.pdf
  {
    code: "RU-KDA", name: "Краснодарский край",
    calendars: [
      {
        year: 2026, complete: false,
        legal_basis: "Закон Краснодарского края от 02.06.2023 № 4909-КЗ, ст. 1; иные региональные даты требуют проверки",
        public_holidays: %w[2026-04-21]
      },
      {
        year: 2027, complete: false,
        legal_basis: "Закон Краснодарского края от 02.06.2023 № 4909-КЗ, ст. 1; иные региональные даты требуют проверки",
        public_holidays: %w[2027-05-11]
      }
    ]
  },
  # https://mtsz.tatarstan.ru/proizvodstvenniy-kalendar-i-razyasnenie-o-norme-8699889.htm (2026)
  # https://pravo.tatarstan.ru/president/ukaz.htm/?npa_id=1776529 (2026)
  # https://pravo.tatarstan.ru/gossov/zakon.htm/?npa_id=77612 (постоянные даты)
  {
    code: "RU-TA", name: "Республика Татарстан",
    calendars: [
      {
        year: 2026, complete: true,
        legal_basis: "Закон РТ от 19.02.1992 № 1448-XII, ст. 1; Указ Раиса РТ от 17.01.2026 № 17",
        public_holidays: %w[2026-03-20 2026-05-27 2026-08-30 2026-11-06]
      },
      {
        year: 2027, complete: false,
        legal_basis: "Закон РТ от 19.02.1992 № 1448-XII, ст. 1; даты Ураза-байрама и Курбан-байрама ожидают указа Раиса РТ",
        public_holidays: %w[2027-08-30 2027-11-06]
      }
    ]
  }
]

regions.each do |attributes|
  region = Region.find_or_create_by!(code: attributes.fetch(:code)) do |record|
    record.name = attributes.fetch(:name)
  end
  attributes.fetch(:calendars).each do |year_attributes|
    calendar = RegionalCalendar.find_or_initialize_by(region:, year: year_attributes.fetch(:year))
    next if calendar.persisted?

    calendar.assign_attributes(year_attributes.except(:year).merge(
      public_holidays: year_attributes.fetch(:public_holidays).map { |value| Date.iso8601(value) }
    ))
    calendar.save!
  end
end
