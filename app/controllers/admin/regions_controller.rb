module Admin
  class RegionsController < ApplicationController
    before_action :require_administrator
    before_action :set_region, only: :edit

    def index
      @regions = Region.includes(:regional_calendars).order(:name)
    end

    def new
      @region = Region.new
    end

    def create
      @region = Region.new(region_params(include_code: true))
      if @region.save
        redirect_to admin_regions_path, notice: "Регион добавлен."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      attributes = region_params(include_code: false)
      set_region
      if @region.update(attributes)
        redirect_to admin_regions_path, notice: "Регион обновлён."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def require_administrator
      head :forbidden unless Current.user.administrator?
    end

    def set_region
      @region = Region.find(params[:id])
    end

    def region_params(include_code:)
      fields = %i[name]
      fields.unshift(:code) if include_code
      raw = params[:region]
      require_known_fields!(raw, *fields, container: "region",
        example: '{"region":{"code":"RU-TA","name":"Республика Татарстан"}}')
      require_string_fields!(raw, *fields) if raw.is_a?(ActionController::Parameters)
      params.expect(region: fields)
    end
  end
end
