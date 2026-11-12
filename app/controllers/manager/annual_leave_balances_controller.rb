module Manager
  class AnnualLeaveBalancesController < ApplicationController
    def index
      return head :forbidden unless Current.user.manager?
      @employees = Current.user.direct_reports.where.not(id: Current.user.id).includes(:annual_leave_years).order(:name)
    end
  end
end
