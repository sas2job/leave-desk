module Admin
  class FederalCalendarsController < ApplicationController
    before_action :require_administrator
    before_action :set_calendar, only: %i[edit update]

    def index
      @calendars = FederalCalendar.order(year: :desc)
    end

    def import
      upload = params[:calendar_file]
      unless upload.is_a?(ActionDispatch::Http::UploadedFile)
        raise FederalCalendarImporter::InvalidFile, "Выберите файл JSON"
      end

      calendar = FederalCalendarImporter.call(upload.tempfile, replace: params[:replace] == "1")
      redirect_to admin_federal_calendars_path, notice: "Календарь #{calendar.year} года импортирован."
    rescue FederalCalendarImporter::InvalidFile => error
      @import_error = error.message
      @calendars = FederalCalendar.order(year: :desc)
      render :index, status: :unprocessable_entity
    end

    def new
      year = Date.current.year
      year += 1 while FederalCalendar.exists?(year:) && year < 2100
      @calendar = FederalCalendar.new(year:,
        public_holidays: RussianFederalHoliday.fixed_dates_for(year))
    end

    def create
      @calendar = FederalCalendar.new(calendar_params(include_year: true))
      if @calendar.save
        redirect_to admin_federal_calendars_path, notice: "Федеральный календарь сохранён."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @calendar.update(calendar_params(include_year: false))
        redirect_to admin_federal_calendars_path, notice: "Федеральный календарь обновлён."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def require_administrator
      head :forbidden unless Current.user.administrator?
    end

    def set_calendar
      @calendar = FederalCalendar.find(params[:id])
    end

    def calendar_params(include_year:)
      fields = %i[legal_basis public_holidays_input transfers_input]
      fields.unshift(:year) if include_year
      require_string_fields!(params.expect(federal_calendar: fields), *fields)
    end
  end
end
