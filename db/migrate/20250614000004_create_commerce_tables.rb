class CreateCommerceTables < ActiveRecord::Migration[8.1]
  def change
    create_table :store_categories do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :store_categories, :slug, unique: true

    create_table :store_products do |t|
      t.string :public_id, null: false
      t.references :store_category, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :product_type, null: false
      t.string :status, null: false, default: "draft"
      t.integer :price_cents, null: false, default: 0
      t.string :currency, null: false, default: "CNY"
      t.integer :stock
      t.integer :purchase_limit
      t.jsonb :fulfillment_config, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :store_products, :public_id, unique: true
    add_index :store_products, :slug, unique: true

    create_table :store_product_variants do |t|
      t.references :store_product, null: false, foreign_key: true
      t.string :name, null: false
      t.string :sku, null: false
      t.integer :price_cents, null: false
      t.integer :stock
      t.jsonb :fulfillment_config, null: false, default: {}
      t.timestamps
    end
    add_index :store_product_variants, :sku, unique: true

    create_table :store_coupons do |t|
      t.string :code, null: false
      t.string :discount_type, null: false
      t.integer :discount_value, null: false
      t.integer :min_amount_cents, null: false, default: 0
      t.integer :usage_limit
      t.integer :used_count, null: false, default: 0
      t.datetime :starts_at
      t.datetime :ends_at
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :store_coupons, :code, unique: true

    create_table :store_carts do |t|
      t.references :user, foreign_key: true
      t.string :session_token
      t.timestamps
    end
    add_index :store_carts, :session_token, unique: true

    create_table :store_cart_items do |t|
      t.references :store_cart, null: false, foreign_key: true
      t.references :store_product, null: false, foreign_key: true
      t.references :store_product_variant, foreign_key: true
      t.integer :quantity, null: false, default: 1
      t.timestamps
    end
    add_index :store_cart_items, [ :store_cart_id, :store_product_id, :store_product_variant_id ], unique: true, name: "index_cart_items_unique"

    create_table :store_orders do |t|
      t.string :public_id, null: false
      t.string :order_number, null: false
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.integer :subtotal_cents, null: false, default: 0
      t.integer :discount_cents, null: false, default: 0
      t.integer :total_cents, null: false, default: 0
      t.string :currency, null: false, default: "CNY"
      t.references :store_coupon, foreign_key: true
      t.text :notes
      t.timestamps
    end
    add_index :store_orders, :public_id, unique: true
    add_index :store_orders, :order_number, unique: true
    add_index :store_orders, :status

    create_table :store_order_items do |t|
      t.references :store_order, null: false, foreign_key: true
      t.references :store_product, foreign_key: true
      t.references :store_product_variant, foreign_key: true
      t.string :product_name, null: false
      t.string :variant_name
      t.integer :unit_price_cents, null: false
      t.integer :quantity, null: false, default: 1
      t.integer :total_cents, null: false
      t.jsonb :fulfillment_snapshot, null: false, default: {}
      t.timestamps
    end

    create_table :store_order_events do |t|
      t.references :store_order, null: false, foreign_key: true
      t.string :event_type, null: false
      t.string :from_status
      t.string :to_status
      t.jsonb :metadata, null: false, default: {}
      t.references :actor, foreign_key: { to_table: :users }
      t.timestamps
    end

    create_table :payment_records do |t|
      t.references :store_order, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :status, null: false, default: "pending"
      t.integer :amount_cents, null: false
      t.string :currency, null: false, default: "CNY"
      t.string :provider_payment_id
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :payment_records, [ :provider, :provider_payment_id ], unique: true

    create_table :payment_webhook_events do |t|
      t.string :provider, null: false
      t.string :event_id, null: false
      t.string :event_type, null: false
      t.jsonb :payload, null: false, default: {}
      t.string :status, null: false, default: "received"
      t.datetime :processed_at
      t.text :error_message
      t.timestamps
    end
    add_index :payment_webhook_events, [ :provider, :event_id ], unique: true

    create_table :payment_attempts do |t|
      t.references :payment_record, null: false, foreign_key: true
      t.string :status, null: false
      t.jsonb :request_data, null: false, default: {}
      t.jsonb :response_data, null: false, default: {}
      t.timestamps
    end

    create_table :store_refunds do |t|
      t.references :store_order, null: false, foreign_key: true
      t.references :payment_record, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.integer :amount_cents, null: false
      t.string :reason
      t.references :requested_by, foreign_key: { to_table: :users }
      t.references :approved_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    create_table :store_fulfillments do |t|
      t.references :store_order, null: false, foreign_key: true
      t.references :store_order_item, null: false, foreign_key: true
      t.string :delivery_id, null: false
      t.string :status, null: false, default: "pending"
      t.integer :attempts_count, null: false, default: 0
      t.text :last_error
      t.datetime :fulfilled_at
      t.timestamps
    end
    add_index :store_fulfillments, :delivery_id, unique: true

    create_table :store_fulfillment_attempts do |t|
      t.references :store_fulfillment, null: false, foreign_key: true
      t.string :status, null: false
      t.jsonb :request_data, null: false, default: {}
      t.jsonb :response_data, null: false, default: {}
      t.timestamps
    end

    create_table :payment_provider_configs do |t|
      t.string :provider, null: false
      t.text :encrypted_credentials
      t.boolean :enabled, null: false, default: false
      t.jsonb :settings, null: false, default: {}
      t.timestamps
    end
    add_index :payment_provider_configs, :provider, unique: true
  end
end
