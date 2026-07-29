class CreateInventoryLedger < ActiveRecord::Migration[8.0]
  def change
    create_table :store_inventory_reservations do |t|
      t.references :store_order, null: false, foreign_key: true
      t.references :store_order_item, null: false, foreign_key: true
      t.references :target, polymorphic: true, null: false
      t.string :status, null: false, default: "active"
      t.integer :quantity, null: false
      t.string :idempotency_key, null: false
      t.datetime :expires_at, null: false
      t.datetime :reserved_at, null: false
      t.datetime :confirmed_at
      t.datetime :released_at
      t.string :release_reason
      t.integer :lock_version, null: false, default: 0
      t.timestamps

      t.index :store_order_item_id, unique: true, name: "idx_inventory_reservations_order_item"
      t.index :idempotency_key, unique: true
      t.index %i[status expires_at], name: "idx_inventory_reservations_expiry"
      t.index %i[target_type target_id status], name: "idx_inventory_reservations_target_status"
      t.check_constraint("quantity > 0", name: "chk_inventory_reservations_quantity")
      t.check_constraint(
        "status IN ('active', 'confirmed', 'released', 'expired')",
        name: "chk_inventory_reservations_status"
      )
    end

    create_table :store_inventory_movements do |t|
      t.string :public_id, null: false
      t.references :target, polymorphic: true, null: false
      t.references :store_inventory_reservation, foreign_key: true
      t.references :store_order, foreign_key: true
      t.references :store_order_item, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      t.string :movement_type, null: false
      t.integer :quantity, null: false
      t.integer :available_delta, null: false, default: 0
      t.integer :reserved_delta, null: false, default: 0
      t.integer :sold_delta, null: false, default: 0
      t.integer :available_after
      t.integer :reserved_after, null: false, default: 0
      t.integer :sold_after, null: false, default: 0
      t.string :idempotency_key, null: false
      t.string :request_id
      t.text :reason
      t.jsonb :metadata, null: false, default: {}
      t.datetime :created_at, null: false

      t.index :public_id, unique: true
      t.index :idempotency_key, unique: true
      t.index %i[target_type target_id created_at], name: "idx_inventory_movements_target_time"
      t.index :request_id
      t.check_constraint("quantity > 0", name: "chk_inventory_movements_quantity")
      t.check_constraint(
        "movement_type IN ('reserve', 'confirm', 'release', 'expire', 'refund', 'damage', 'adjustment', 'recovery')",
        name: "chk_inventory_movements_type"
      )
    end
  end
end
