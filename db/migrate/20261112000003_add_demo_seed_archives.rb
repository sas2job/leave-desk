class AddDemoSeedArchives < ActiveRecord::Migration[8.1]
  def change
    create_table :demo_seed_archives do |t|
      t.string :plan_digest, null: false, limit: 64
      t.jsonb :archived_data, null: false
      t.jsonb :summary, null: false
      t.timestamps
    end
    add_index :demo_seed_archives, :plan_digest, unique: true
  end
end
