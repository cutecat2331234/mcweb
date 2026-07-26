class AddProviderTrackingToStoreRefunds < ActiveRecord::Migration[8.1]
  def change
    add_column :store_refunds, :provider_refund_id, :string
    add_column :store_refunds, :provider_status, :string
    add_column :store_refunds, :provider_error_code, :string
    add_column :store_refunds, :provider_metadata, :jsonb, null: false, default: {}
    add_column :store_refunds, :processing_started_at, :datetime

    add_index :store_refunds, :provider_refund_id, unique: true,
      where: "provider_refund_id IS NOT NULL"
    add_index :store_refunds, [ :status, :processing_started_at ],
      name: "index_store_refunds_on_status_and_processing_started_at"
  end
end
