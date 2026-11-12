class AnnualLeaveAdjustment < ApplicationRecord
  belongs_to :annual_leave_year
  belongs_to :actor, class_name: "User"
  validates :reason, presence: true, length: { maximum: 200 }
  before_update { throw :abort }
  before_destroy { throw :abort }
end
