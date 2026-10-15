class Session < ApplicationRecord
  LIFETIME = 30.days
  PRUNE_BATCH_SIZE = 1_000

  belongs_to :user

  def self.prune_expired!(now: Time.current)
    where("created_at < ?", now - LIFETIME).in_batches(of: PRUNE_BATCH_SIZE) do |batch|
      batch.delete_all
    end
  end

  def expired?
    created_at < LIFETIME.ago
  end
end
