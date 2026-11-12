class AnnualLeaveBalancesController < ApplicationController
  def show
    @years = Current.user.annual_leave_years.includes(annual_leave_bookings: :leave_request).order(:starts_on)
  end
end
