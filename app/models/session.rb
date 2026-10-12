class Session < ApplicationRecord
  LIFETIME = 30.days

  belongs_to :user

  def expired?
    created_at < LIFETIME.ago
  end
end
