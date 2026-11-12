class DemoSeedArchive < ApplicationRecord
  validates :plan_digest, presence: true, uniqueness: true, format: { with: /\A[a-f0-9]{64}\z/ }
  validates :archived_data, :summary, presence: true
  before_update { throw :abort }
  before_destroy { throw :abort }
end
