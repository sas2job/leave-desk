class CreateLeaveTypes < ActiveRecord::Migration[8.1]
  def change
    create_table :leave_types do |t|
      t.string :name, null: false
      t.string :code, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :leave_types, :code, unique: true
  end
end
