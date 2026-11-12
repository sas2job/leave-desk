module Admin
  class AnnualLeaveYearsController < ApplicationController
    rescue_from LeaveRequest::ReviewNotAuthorized, with: -> { head :not_found }
    before_action :require_administrator
    before_action :set_employee

    def index
      @year = @employee.annual_leave_years.new(entitlement_days: @employee.annual_default_days, opening_used_days: 0)
      load_years
    end

    def create
      attributes = year_params
      @year = AnnualLeaveYear.record!(employee: @employee, by: Current.user, **attributes)
      redirect_to balance_location, notice: "Рабочий год и начальный остаток сохранены."
    rescue ActiveRecord::RecordInvalid => error
      @year = error.record
      load_years
      render "admin/annual_leave_years/index", status: :unprocessable_entity
    rescue ActiveRecord::StatementInvalid => error
      raise unless error.cause.is_a?(PG::ExclusionViolation)
      redirect_to balance_location, alert: "Рабочие годы сотрудника пересекаются."
    end

    def update
      @year = @employee.annual_leave_years.find(params[:id])
      attributes = correction_params
      @year.revise!(by: Current.user, **attributes)
      redirect_to balance_location, notice: "Корректировка остатка сохранена в истории."
    rescue ActiveRecord::RecordInvalid => error
      redirect_to balance_location, alert: error.record.errors.full_messages.to_sentence
    rescue LeaveRequest::InvalidTransition => error
      redirect_to balance_location, alert: error.message
    end

    private

    def require_administrator
      head :forbidden unless Current.user.administrator?
    end

    def balance_location
      admin_user_annual_leave_years_path(@employee)
    end

    def set_employee
      @balance_namespace = :admin
      @employee = User.find(params[:user_id])
    end

    def load_years
      @years = @employee.annual_leave_years.includes(:recorded_by, annual_leave_adjustments: :actor).order(:starts_on)
    end

    def year_params
      fields = %i[starts_on ends_on entitlement_days opening_used_days basis history_confirmed]
      require_known_fields!(params[:annual_leave_year], *fields, container: "annual_leave_year", example: '{"annual_leave_year":{}}')
      if params[:annual_leave_year].is_a?(ActionController::Parameters)
        require_string_fields!(params[:annual_leave_year], :starts_on, :ends_on, :basis, :opening_used_days, :history_confirmed)
        require_identifier_fields!(params[:annual_leave_year], :entitlement_days)
      end
      attributes = params.expect(annual_leave_year: fields).to_h.symbolize_keys
      require_string_fields!(attributes, :starts_on, :ends_on, :basis, :opening_used_days, :history_confirmed)
      require_identifier_fields!(attributes, :entitlement_days)
      attributes[:history_confirmed] = attributes[:history_confirmed] == "1"
      %i[starts_on ends_on].each do |field|
        raw = attributes[field]
        attributes[field] = raw&.match?(/\A\d{4}-\d{2}-\d{2}\z/) ? Date.iso8601(raw) : nil
      rescue Date::Error
        attributes[field] = nil
      end
      attributes
    end

    def correction_params
      fields = %i[entitlement_days opening_used_days reason]
      require_known_fields!(params[:annual_leave_adjustment], *fields, container: "annual_leave_adjustment", example: '{"annual_leave_adjustment":{}}')
      if params[:annual_leave_adjustment].is_a?(ActionController::Parameters)
        require_string_fields!(params[:annual_leave_adjustment], :opening_used_days, :reason)
        require_identifier_fields!(params[:annual_leave_adjustment], :entitlement_days)
      end
      attributes = params.expect(annual_leave_adjustment: fields).to_h.symbolize_keys
      require_string_fields!(attributes, :opening_used_days, :reason)
      require_identifier_fields!(attributes, :entitlement_days)
      attributes
    end
  end
end
