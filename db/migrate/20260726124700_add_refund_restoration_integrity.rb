class AddRefundRestorationIntegrity < ActiveRecord::Migration[8.1]
  def change
    add_column :store_refunds, :provider_confirmed_at, :datetime
    add_column :store_refunds, :restoration_status, :string, null: false, default: "pending"
    add_column :store_refunds, :restoration_attempts, :integer, null: false, default: 0
    add_column :store_refunds, :restoration_error, :text
    add_column :store_refunds, :restoration_completed_at, :datetime

    add_column :store_user_entitlements, :revoked_at, :datetime

    reversible do |direction|
      direction.up do
        execute <<~SQL.squish
          UPDATE store_refunds
          SET provider_confirmed_at = COALESCE(processing_started_at, updated_at)
          WHERE status = 'completed' OR provider_status = 'succeeded'
        SQL
        execute <<~SQL.squish
          UPDATE store_refunds
          SET restoration_status = 'completed',
              restoration_completed_at = updated_at
          WHERE status = 'completed'
        SQL
      end
    end

    add_check_constraint :store_refunds, "amount_cents > 0",
      name: "store_refunds_amount_cents_positive"
    add_check_constraint :store_refunds,
      "restoration_status IN ('pending', 'processing', 'failed', 'completed')",
      name: "store_refunds_restoration_status_valid"

    add_index :store_refunds, [ :restoration_status, :processing_started_at ],
      name: "index_store_refunds_on_restoration_recovery"
    add_index :store_user_entitlements, :revoked_at
  end
end
