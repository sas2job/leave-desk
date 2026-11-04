module Admin
  class RegionalCalendarsController < ApplicationController
    before_action :require_administrator
    before_action :set_calendar, only: :edit
    before_action :set_region_options, only: %i[new edit]

    def index
      @calendars = RegionalCalendar.includes(:region).order(year: :desc, region_id: :asc)
    end

    def new
      @calendar = RegionalCalendar.new(year: Date.current.year)
    end

    def create
      attributes = calendar_params(include_identity: true)
      @calendar = RegionalCalendar.new(attributes)
      if @calendar.save
        redirect_to admin_regional_calendars_path, notice: "Региональный календарь сохранён."
      else
        set_region_options
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      attributes = calendar_params(include_identity: false)
      set_calendar
      if @calendar.update(attributes)
        redirect_to admin_regional_calendars_path, notice: "Региональный календарь обновлён."
      else
        set_region_options
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def require_administrator
      head :forbidden unless Current.user.administrator?
    end

    def set_calendar
      @calendar = RegionalCalendar.find(params[:id])
    end

    def set_region_options
      @region_options = Region.order(:name)
    end

    def calendar_params(include_identity:)
      fields = %i[legal_basis public_holidays_input additional_days_off_input complete]
      fields.unshift(:year, :region_id) if include_identity
      raw = params[:regional_calendar]
      require_known_fields!(raw, *fields, container: "regional_calendar",
        example: '{"regional_calendar":{"region_id":"1","year":"2026","legal_basis":"НПА",' \
          '"public_holidays_input":"2026-11-06","additional_days_off_input":"","complete":"1"}}')
      return params.expect(regional_calendar: fields) unless raw.is_a?(ActionController::Parameters)

      require_string_fields!(raw, :legal_basis, :public_holidays_input, :additional_days_off_input)
      unless !raw.key?(:complete) || [ "0", "1" ].include?(raw[:complete])
        raise ActionController::BadRequest, "Invalid calendar completeness value"
      end
      if include_identity
        require_string_fields!(raw, :year)
        require_identifier_fields!(raw, :region_id)
      end
      params.expect(regional_calendar: fields)
    end
  end
end
