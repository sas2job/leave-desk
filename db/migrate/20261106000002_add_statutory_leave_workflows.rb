class AddStatutoryLeaveWorkflows < ActiveRecord::Migration[8.1]
  def up
    add_column :leave_requests, :legal_kind, :integer, null: false, default: 0
    add_column :leave_requests, :child_born_on, :date
    add_column :leave_requests, :care_relationship, :integer
    add_column :leave_requests, :returned_on, :date
    add_column :leave_requests, :birthday_claim_year, :integer
    add_column :leave_requests, :birthday_used, :boolean, null: false, default: false
    add_reference :leave_requests, :resumes_request, foreign_key: { to_table: :leave_requests }
    remove_check_constraint :leave_requests, name: "leave_requests_valid_status"
    add_check_constraint :leave_requests, "status IN (0, 1, 2, 3, 4, 5)", name: "leave_requests_valid_status"
    add_check_constraint :leave_requests, "legal_kind IN (0, 1, 2, 3, 4)", name: "leave_requests_valid_legal_kind"
    add_check_constraint :leave_requests,
      "birthday_claim_year IS NULL OR birthday_claim_year = EXTRACT(YEAR FROM starts_on)::integer",
      name: "leave_requests_birthday_claim_year"
    add_check_constraint :leave_requests,
      "legal_kind <> 4 OR (starts_on = ends_on AND birthday_claim_year IS NOT NULL)",
      name: "leave_requests_birthday_one_day"
    execute <<~SQL
      UPDATE leave_requests requests SET birthday_used = true
      FROM leave_types types, users employees
      WHERE requests.leave_type_id = types.id AND types.code = 'BIRTHDAY'
        AND employees.id = requests.employee_id AND requests.status = 3
        AND EXISTS (SELECT 1 FROM leave_request_events events
          WHERE events.leave_request_id = requests.id AND events.event_type = 3 AND events.from_status = 1
            AND requests.starts_on <= (events.occurred_at AT TIME ZONE employees.time_zone)::date)
    SQL
    execute <<~SQL
      WITH claims AS (
        SELECT requests.id, EXTRACT(YEAR FROM requests.starts_on)::integer AS claim_year,
          row_number() OVER (PARTITION BY requests.employee_id, EXTRACT(YEAR FROM requests.starts_on)
            ORDER BY requests.id) AS position
        FROM leave_requests requests JOIN leave_types types ON types.id = requests.leave_type_id
        WHERE types.code = 'BIRTHDAY' AND (requests.status IN (0, 1) OR requests.birthday_used)
      )
      UPDATE leave_requests requests SET birthday_claim_year = claims.claim_year
      FROM claims WHERE claims.id = requests.id AND claims.position = 1
    SQL
    add_index :leave_requests, %i[employee_id birthday_claim_year], unique: true,
      where: "birthday_claim_year IS NOT NULL AND (status IN (0, 1) OR birthday_used)",
      name: "leave_requests_one_birthday_per_year"
    add_check_constraint :leave_requests,
      "legal_kind = 0 OR (start_minute IS NOT NULL AND end_minute IS NOT NULL AND start_minute = 0 AND end_minute = 1440)",
      name: "leave_requests_statutory_full_days"
    add_check_constraint :leave_requests,
      "legal_kind <> 3 OR (child_born_on IS NOT NULL AND isfinite(child_born_on) " \
        "AND child_born_on BETWEEN DATE '2000-01-01' AND DATE '2100-12-31' " \
        "AND starts_on >= child_born_on AND ends_on <= (child_born_on + interval '3 years' + " \
        "CASE WHEN to_char(child_born_on, 'MM-DD') = '02-29' THEN interval '1 day' ELSE interval '0 days' END)::date " \
        "AND care_relationship IS NOT NULL AND care_relationship IN (0, 1, 2, 3, 4))",
      name: "leave_requests_childcare_period"
    add_check_constraint :leave_requests,
      "(status = 5 AND legal_kind = 3 AND returned_on IS NOT NULL AND isfinite(returned_on) " \
        "AND returned_on >= starts_on AND returned_on <= ends_on) OR (status <> 5 AND returned_on IS NULL)",
      name: "leave_requests_childcare_return"
    add_check_constraint :leave_requests, "resumes_request_id IS NULL OR resumes_request_id <> id",
      name: "leave_requests_resume_not_self"
    execute "ALTER TABLE leave_requests DROP CONSTRAINT leave_requests_no_overlapping_active_periods"
    execute <<~SQL
      ALTER TABLE leave_requests ADD CONSTRAINT leave_requests_no_overlapping_active_periods
      EXCLUDE USING gist (
        employee_id WITH =,
        tsrange(starts_on + (COALESCE(start_minute, start_part * 720) * interval '1 minute'),
          CASE WHEN COALESCE(recalled_on, returned_on) IS NOT NULL
            THEN COALESCE(recalled_on, returned_on)::timestamp
            ELSE ends_on + (COALESCE(end_minute, (end_part + 1) * 720) * interval '1 minute') END, '[)') WITH &&
      ) WHERE (status IN (0, 1, 4, 5))
    SQL
    remove_check_constraint :leave_request_events, name: "leave_request_events_valid_type"
    add_check_constraint :leave_request_events, "event_type BETWEEN 0 AND 13", name: "leave_request_events_valid_type"
    remove_check_constraint :leave_request_events, name: "leave_request_events_valid_to_status"
    add_check_constraint :leave_request_events, "to_status IN (0, 1, 2, 3, 4, 5)", name: "leave_request_events_valid_to_status"

    create_table :leave_legal_reviews do |t|
      t.references :leave_request, null: false, foreign_key: true, index: { unique: true }
      t.references :reviewer, null: false, foreign_key: { to_table: :users }
      t.boolean :annual, null: false, default: false
      t.boolean :conditions_confirmed, null: false, default: false
      t.boolean :age_boundary_confirmed, null: false, default: false
      t.text :document_reference
      t.date :document_starts_on
      t.date :document_ends_on
      t.date :working_year_starts_on
      t.date :working_year_ends_on
      t.integer :entitlement_days
      t.datetime :confirmed_at, null: false
      t.timestamps
    end
    add_check_constraint :leave_legal_reviews, "conditions_confirmed", name: "leave_legal_reviews_confirmed"
    add_check_constraint :leave_legal_reviews,
      "(annual AND working_year_starts_on IS NOT NULL AND working_year_ends_on IS NOT NULL " \
        "AND isfinite(working_year_starts_on) AND isfinite(working_year_ends_on) " \
        "AND working_year_ends_on >= working_year_starts_on AND entitlement_days IS NOT NULL AND entitlement_days >= 28) " \
        "OR (NOT annual AND document_reference IS NOT NULL AND length(btrim(document_reference)) > 0)",
      name: "leave_legal_reviews_basis_required"
    execute <<~SQL
      INSERT INTO leave_types (code, name, active, holiday_handling, created_at, updated_at)
      VALUES ('MATERNITY', 'Отпуск по беременности и родам', true, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
             ('CHILDCARE', 'Отпуск по уходу за ребёнком', true, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      ON CONFLICT (code) DO NOTHING
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Statutory registrations and childcare history must be retained"
  end
end
