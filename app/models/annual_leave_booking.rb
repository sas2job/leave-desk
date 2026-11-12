class AnnualLeaveBooking < ApplicationRecord
  belongs_to :leave_request
  belongs_to :annual_leave_year
  enum :status, { reserved: 0, committed: 1, released: 2 }, prefix: :booking
  validates :minutes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  before_destroy { throw :abort }
end
