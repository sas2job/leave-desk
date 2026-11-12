module Manager
  class AnnualLeaveYearsController < Admin::AnnualLeaveYearsController
    def index
      super
      render "admin/annual_leave_years/index"
    end

    def policy
      fields = %i[extended_annual_leave annual_base_days annual_additional_days annual_leave_basis]
      require_known_fields!(params[:annual_policy], *fields, container: "annual_policy", example: '{"annual_policy":{}}')
      require_string_fields!(params[:annual_policy], *fields) if params[:annual_policy].is_a?(ActionController::Parameters)
      attributes = params.expect(annual_policy: fields)
      require_string_fields!(attributes, *fields)
      unless [ "0", "1" ].include?(attributes[:extended_annual_leave]) &&
          attributes[:annual_base_days].to_s.match?(/\A\d+\z/) && attributes[:annual_additional_days].to_s.match?(/\A\d+\z/)
        raise ActionController::BadRequest, "Invalid annual policy"
      end
      @employee.with_lock do
        AnnualLeaveYear.require_editor!(employee: @employee, by: Current.user)
        @employee.update!(attributes)
      end
      redirect_to balance_location, notice: "Продолжительность отпуска обновлена. Существующие рабочие годы не изменены."
    rescue ActiveRecord::RecordInvalid => error
      redirect_to balance_location, alert: error.record.errors.full_messages.to_sentence
    rescue LeaveRequest::ReviewNotAuthorized
      head :not_found
    end

    private

    def require_administrator
      head :forbidden unless Current.user.manager?
    end

    def set_employee
      @balance_namespace = :manager
      @employee = Current.user.direct_reports.where.not(id: Current.user.id).find(params[:user_id])
    end

    def balance_location
      manager_user_annual_leave_years_path(@employee)
    end
  end
end
