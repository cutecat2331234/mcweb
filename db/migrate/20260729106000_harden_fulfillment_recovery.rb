class HardenFulfillmentRecovery < ActiveRecord::Migration[8.0]
  def up
    add_column :store_fulfillments, :next_attempt_at, :datetime
    add_column :store_fulfillments, :max_attempts, :integer, null: false, default: 5
    add_column :store_fulfillments, :last_result_summary, :jsonb, null: false, default: {}
    add_column :store_fulfillments, :cancelled_at, :datetime
    add_column :store_fulfillments, :cancel_reason, :text
    add_column :store_fulfillments, :lock_version, :integer, null: false, default: 0
    add_index :store_fulfillments, %i[status next_attempt_at], name: "idx_store_fulfillments_recovery"

    add_column :store_fulfillment_attempts, :attempt_number, :integer
    add_column :store_fulfillment_attempts, :idempotency_key, :string
    add_column :store_fulfillment_attempts, :trigger, :string, null: false, default: "automatic"
    add_column :store_fulfillment_attempts, :action, :string, null: false, default: "dispatch"
    add_column :store_fulfillment_attempts, :error_code, :string
    add_column :store_fulfillment_attempts, :result_summary, :jsonb, null: false, default: {}
    add_column :store_fulfillment_attempts, :started_at, :datetime
    add_column :store_fulfillment_attempts, :completed_at, :datetime
    add_column :store_fulfillment_attempts, :next_retry_at, :datetime
    add_column :store_fulfillment_attempts, :reason, :text
    add_column :store_fulfillment_attempts, :request_id, :string
    add_reference :store_fulfillment_attempts, :actor, foreign_key: { to_table: :users }

    execute <<~SQL
      UPDATE store_fulfillment_attempts
      SET attempt_number = id,
          idempotency_key = 'legacy-fulfillment-attempt-' || id
    SQL
    change_column_null :store_fulfillment_attempts, :attempt_number, false
    change_column_null :store_fulfillment_attempts, :idempotency_key, false
    add_index :store_fulfillment_attempts, :idempotency_key, unique: true
    add_index :store_fulfillment_attempts,
              %i[store_fulfillment_id attempt_number],
              unique: true,
              name: "idx_fulfillment_attempt_number"
    add_index :store_fulfillment_attempts, :request_id
  end

  def down
    remove_index :store_fulfillment_attempts, :request_id
    remove_index :store_fulfillment_attempts, name: "idx_fulfillment_attempt_number"
    remove_index :store_fulfillment_attempts, :idempotency_key
    remove_reference :store_fulfillment_attempts, :actor, foreign_key: { to_table: :users }
    remove_columns :store_fulfillment_attempts,
                   :attempt_number,
                   :idempotency_key,
                   :trigger,
                   :action,
                   :error_code,
                   :result_summary,
                   :started_at,
                   :completed_at,
                   :next_retry_at,
                   :reason,
                   :request_id

    remove_index :store_fulfillments, name: "idx_store_fulfillments_recovery"
    remove_columns :store_fulfillments,
                   :next_attempt_at,
                   :max_attempts,
                   :last_result_summary,
                   :cancelled_at,
                   :cancel_reason,
                   :lock_version
  end
end
