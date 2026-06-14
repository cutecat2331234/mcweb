# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2025_06_14_000005) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "audit_logs", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "actor_id"
    t.jsonb "after_state", default: {}, null: false
    t.jsonb "before_state", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.jsonb "metadata", default: {}, null: false
    t.text "reason"
    t.bigint "resource_id"
    t.string "resource_public_id"
    t.string "resource_type"
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["actor_id"], name: "index_audit_logs_on_actor_id"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
    t.index ["resource_type", "resource_id"], name: "index_audit_logs_on_resource_type_and_resource_id"
  end

  create_table "forum_categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_forum_categories_on_slug", unique: true
  end

  create_table "forum_mutes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id", null: false
    t.datetime "expires_at"
    t.bigint "forum_section_id"
    t.text "reason"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["created_by_id"], name: "index_forum_mutes_on_created_by_id"
    t.index ["forum_section_id"], name: "index_forum_mutes_on_forum_section_id"
    t.index ["user_id"], name: "index_forum_mutes_on_user_id"
  end

  create_table "forum_post_edits", force: :cascade do |t|
    t.text "body_after"
    t.text "body_before"
    t.datetime "created_at", null: false
    t.bigint "editor_id", null: false
    t.bigint "forum_post_id", null: false
    t.datetime "updated_at", null: false
    t.index ["editor_id"], name: "index_forum_post_edits_on_editor_id"
    t.index ["forum_post_id"], name: "index_forum_post_edits_on_forum_post_id"
  end

  create_table "forum_posts", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.datetime "edited_at"
    t.integer "floor_number", null: false
    t.bigint "forum_topic_id", null: false
    t.bigint "quoted_post_id"
    t.string "status", default: "published", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["deleted_at"], name: "index_forum_posts_on_deleted_at"
    t.index ["forum_topic_id", "floor_number"], name: "index_forum_posts_on_forum_topic_id_and_floor_number", unique: true
    t.index ["forum_topic_id"], name: "index_forum_posts_on_forum_topic_id"
    t.index ["quoted_post_id"], name: "index_forum_posts_on_quoted_post_id"
    t.index ["user_id"], name: "index_forum_posts_on_user_id"
  end

  create_table "forum_reactions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "emoji", null: false
    t.bigint "forum_post_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["forum_post_id"], name: "index_forum_reactions_on_forum_post_id"
    t.index ["user_id", "forum_post_id", "emoji"], name: "index_forum_reactions_on_user_id_and_forum_post_id_and_emoji", unique: true
    t.index ["user_id"], name: "index_forum_reactions_on_user_id"
  end

  create_table "forum_read_states", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "forum_topic_id", null: false
    t.integer "last_read_floor", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["forum_topic_id"], name: "index_forum_read_states_on_forum_topic_id"
    t.index ["user_id", "forum_topic_id"], name: "index_forum_read_states_on_user_id_and_forum_topic_id", unique: true
    t.index ["user_id"], name: "index_forum_read_states_on_user_id"
  end

  create_table "forum_reports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "reason", null: false
    t.bigint "reportable_id", null: false
    t.string "reportable_type", null: false
    t.bigint "reporter_id", null: false
    t.text "review_note"
    t.datetime "reviewed_at"
    t.bigint "reviewer_id"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["reportable_type", "reportable_id"], name: "index_forum_reports_on_reportable_type_and_reportable_id"
    t.index ["reporter_id"], name: "index_forum_reports_on_reporter_id"
    t.index ["reviewer_id"], name: "index_forum_reports_on_reviewer_id"
  end

  create_table "forum_sections", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.bigint "forum_category_id", null: false
    t.string "name", null: false
    t.bigint "parent_id"
    t.jsonb "permissions", default: {}, null: false
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["forum_category_id", "slug"], name: "index_forum_sections_on_forum_category_id_and_slug", unique: true
    t.index ["forum_category_id"], name: "index_forum_sections_on_forum_category_id"
    t.index ["parent_id"], name: "index_forum_sections_on_parent_id"
  end

  create_table "forum_subscriptions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "subscribable_id", null: false
    t.string "subscribable_type", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "subscribable_type", "subscribable_id"], name: "idx_on_user_id_subscribable_type_subscribable_id_8ef4ba5a1f", unique: true
    t.index ["user_id"], name: "index_forum_subscriptions_on_user_id"
  end

  create_table "forum_topics", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.boolean "featured", default: false, null: false
    t.bigint "forum_section_id", null: false
    t.bigint "last_post_user_id"
    t.datetime "last_posted_at"
    t.boolean "locked", default: false, null: false
    t.boolean "pinned", default: false, null: false
    t.string "public_id", null: false
    t.integer "replies_count", default: 0, null: false
    t.string "status", default: "published", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "views_count", default: 0, null: false
    t.index ["deleted_at"], name: "index_forum_topics_on_deleted_at"
    t.index ["forum_section_id", "last_posted_at"], name: "index_forum_topics_on_forum_section_id_and_last_posted_at"
    t.index ["forum_section_id"], name: "index_forum_topics_on_forum_section_id"
    t.index ["last_post_user_id"], name: "index_forum_topics_on_last_post_user_id"
    t.index ["public_id"], name: "index_forum_topics_on_public_id", unique: true
    t.index ["user_id"], name: "index_forum_topics_on_user_id"
  end

  create_table "installation_locks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "locked", default: false, null: false
    t.datetime "locked_at"
    t.bigint "locked_by_id"
    t.datetime "updated_at", null: false
    t.index ["locked_by_id"], name: "index_installation_locks_on_locked_by_id"
  end

  create_table "minecraft_connector_tasks", force: :cascade do |t|
    t.datetime "claimed_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "delivery_id"
    t.bigint "minecraft_server_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.jsonb "result", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.bigint "store_fulfillment_id"
    t.string "task_type", null: false
    t.datetime "updated_at", null: false
    t.index ["delivery_id"], name: "index_minecraft_connector_tasks_on_delivery_id", unique: true, where: "(delivery_id IS NOT NULL)"
    t.index ["minecraft_server_id"], name: "index_minecraft_connector_tasks_on_minecraft_server_id"
    t.index ["store_fulfillment_id"], name: "index_minecraft_connector_tasks_on_store_fulfillment_id"
  end

  create_table "minecraft_identities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "identity_type", default: "java", null: false
    t.datetime "linked_at", null: false
    t.bigint "minecraft_server_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "username", null: false
    t.string "uuid", null: false
    t.index ["minecraft_server_id"], name: "index_minecraft_identities_on_minecraft_server_id"
    t.index ["user_id"], name: "index_minecraft_identities_on_user_id"
    t.index ["uuid", "identity_type"], name: "index_minecraft_identities_on_uuid_and_identity_type", unique: true
  end

  create_table "minecraft_link_codes", force: :cascade do |t|
    t.string "code_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "identity_type", default: "java", null: false
    t.bigint "minecraft_server_id", null: false
    t.string "minecraft_username", null: false
    t.string "minecraft_uuid", null: false
    t.datetime "updated_at", null: false
    t.datetime "used_at"
    t.bigint "used_by_id"
    t.index ["code_digest"], name: "index_minecraft_link_codes_on_code_digest", unique: true
    t.index ["minecraft_server_id"], name: "index_minecraft_link_codes_on_minecraft_server_id"
    t.index ["used_by_id"], name: "index_minecraft_link_codes_on_used_by_id"
  end

  create_table "minecraft_processed_deliveries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "delivery_id", null: false
    t.bigint "minecraft_server_id", null: false
    t.jsonb "result", default: {}, null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["minecraft_server_id", "delivery_id"], name: "idx_on_minecraft_server_id_delivery_id_5dd669361e", unique: true
    t.index ["minecraft_server_id"], name: "index_minecraft_processed_deliveries_on_minecraft_server_id"
  end

  create_table "minecraft_servers", force: :cascade do |t|
    t.string "address"
    t.string "connector_secret_fingerprint"
    t.datetime "created_at", null: false
    t.text "encrypted_connector_secret"
    t.datetime "last_heartbeat_at"
    t.integer "max_players", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.integer "online_players", default: 0, null: false
    t.integer "port", default: 25565, null: false
    t.string "public_id", null: false
    t.string "status", default: "offline", null: false
    t.datetime "updated_at", null: false
    t.string "version"
    t.index ["public_id"], name: "index_minecraft_servers_on_public_id", unique: true
  end

  create_table "notification_preferences", force: :cascade do |t|
    t.string "channel", null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.string "notification_type", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "channel", "notification_type"], name: "idx_on_user_id_channel_notification_type_391233d590", unique: true
    t.index ["user_id"], name: "index_notification_preferences_on_user_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "notification_type", null: false
    t.datetime "read_at"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "read_at"], name: "index_notifications_on_user_id_and_read_at"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "payment_attempts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "payment_record_id", null: false
    t.jsonb "request_data", default: {}, null: false
    t.jsonb "response_data", default: {}, null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["payment_record_id"], name: "index_payment_attempts_on_payment_record_id"
  end

  create_table "payment_provider_configs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled", default: false, null: false
    t.text "encrypted_credentials"
    t.string "provider", null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["provider"], name: "index_payment_provider_configs_on_provider", unique: true
  end

  create_table "payment_records", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "CNY", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "provider", null: false
    t.string "provider_payment_id"
    t.string "status", default: "pending", null: false
    t.bigint "store_order_id", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "provider_payment_id"], name: "index_payment_records_on_provider_and_provider_payment_id", unique: true
    t.index ["store_order_id"], name: "index_payment_records_on_store_order_id"
  end

  create_table "payment_webhook_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "event_id", null: false
    t.string "event_type", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "processed_at"
    t.string "provider", null: false
    t.string "status", default: "received", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "event_id"], name: "index_payment_webhook_events_on_provider_and_event_id", unique: true
  end

  create_table "permissions", force: :cascade do |t|
    t.string "category", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_permissions_on_key", unique: true
  end

  create_table "rate_limit_counters", force: :cascade do |t|
    t.integer "count", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.datetime "window_start", null: false
    t.index ["key"], name: "index_rate_limit_counters_on_key", unique: true
  end

  create_table "role_permissions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "permission_id", null: false
    t.bigint "role_id", null: false
    t.datetime "updated_at", null: false
    t.index ["permission_id"], name: "index_role_permissions_on_permission_id"
    t.index ["role_id", "permission_id"], name: "index_role_permissions_on_role_id_and_permission_id", unique: true
    t.index ["role_id"], name: "index_role_permissions_on_role_id"
  end

  create_table "roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.string "name", null: false
    t.boolean "system_role", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_roles_on_key", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "ip_address"
    t.datetime "last_active_at"
    t.boolean "remember_me", default: false, null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.bigint "user_id", null: false
    t.index ["expires_at"], name: "index_sessions_on_expires_at"
    t.index ["token_digest"], name: "index_sessions_on_token_digest", unique: true
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "site_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.jsonb "value", default: {}, null: false
    t.index ["key"], name: "index_site_settings_on_key", unique: true
  end

  create_table "store_cart_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "quantity", default: 1, null: false
    t.bigint "store_cart_id", null: false
    t.bigint "store_product_id", null: false
    t.bigint "store_product_variant_id"
    t.datetime "updated_at", null: false
    t.index ["store_cart_id", "store_product_id", "store_product_variant_id"], name: "index_cart_items_unique", unique: true
    t.index ["store_cart_id"], name: "index_store_cart_items_on_store_cart_id"
    t.index ["store_product_id"], name: "index_store_cart_items_on_store_product_id"
    t.index ["store_product_variant_id"], name: "index_store_cart_items_on_store_product_variant_id"
  end

  create_table "store_carts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "session_token"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["session_token"], name: "index_store_carts_on_session_token", unique: true
    t.index ["user_id"], name: "index_store_carts_on_user_id"
  end

  create_table "store_categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_store_categories_on_slug", unique: true
  end

  create_table "store_coupons", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "discount_type", null: false
    t.integer "discount_value", null: false
    t.datetime "ends_at"
    t.integer "min_amount_cents", default: 0, null: false
    t.datetime "starts_at"
    t.datetime "updated_at", null: false
    t.integer "usage_limit"
    t.integer "used_count", default: 0, null: false
    t.index ["code"], name: "index_store_coupons_on_code", unique: true
  end

  create_table "store_fulfillment_attempts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "request_data", default: {}, null: false
    t.jsonb "response_data", default: {}, null: false
    t.string "status", null: false
    t.bigint "store_fulfillment_id", null: false
    t.datetime "updated_at", null: false
    t.index ["store_fulfillment_id"], name: "index_store_fulfillment_attempts_on_store_fulfillment_id"
  end

  create_table "store_fulfillments", force: :cascade do |t|
    t.integer "attempts_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "delivery_id", null: false
    t.datetime "fulfilled_at"
    t.text "last_error"
    t.string "status", default: "pending", null: false
    t.bigint "store_order_id", null: false
    t.bigint "store_order_item_id", null: false
    t.datetime "updated_at", null: false
    t.index ["delivery_id"], name: "index_store_fulfillments_on_delivery_id", unique: true
    t.index ["store_order_id"], name: "index_store_fulfillments_on_store_order_id"
    t.index ["store_order_item_id"], name: "index_store_fulfillments_on_store_order_item_id"
  end

  create_table "store_order_events", force: :cascade do |t|
    t.bigint "actor_id"
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.string "from_status"
    t.jsonb "metadata", default: {}, null: false
    t.bigint "store_order_id", null: false
    t.string "to_status"
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_store_order_events_on_actor_id"
    t.index ["store_order_id"], name: "index_store_order_events_on_store_order_id"
  end

  create_table "store_order_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "fulfillment_snapshot", default: {}, null: false
    t.string "product_name", null: false
    t.integer "quantity", default: 1, null: false
    t.bigint "store_order_id", null: false
    t.bigint "store_product_id"
    t.bigint "store_product_variant_id"
    t.integer "total_cents", null: false
    t.integer "unit_price_cents", null: false
    t.datetime "updated_at", null: false
    t.string "variant_name"
    t.index ["store_order_id"], name: "index_store_order_items_on_store_order_id"
    t.index ["store_product_id"], name: "index_store_order_items_on_store_product_id"
    t.index ["store_product_variant_id"], name: "index_store_order_items_on_store_product_variant_id"
  end

  create_table "store_orders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", default: "CNY", null: false
    t.integer "discount_cents", default: 0, null: false
    t.text "notes"
    t.string "order_number", null: false
    t.string "public_id", null: false
    t.string "status", default: "pending", null: false
    t.bigint "store_coupon_id"
    t.integer "subtotal_cents", default: 0, null: false
    t.integer "total_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["order_number"], name: "index_store_orders_on_order_number", unique: true
    t.index ["public_id"], name: "index_store_orders_on_public_id", unique: true
    t.index ["status"], name: "index_store_orders_on_status"
    t.index ["store_coupon_id"], name: "index_store_orders_on_store_coupon_id"
    t.index ["user_id"], name: "index_store_orders_on_user_id"
  end

  create_table "store_product_variants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "fulfillment_config", default: {}, null: false
    t.string "name", null: false
    t.integer "price_cents", null: false
    t.string "sku", null: false
    t.integer "stock"
    t.bigint "store_product_id", null: false
    t.datetime "updated_at", null: false
    t.index ["sku"], name: "index_store_product_variants_on_sku", unique: true
    t.index ["store_product_id"], name: "index_store_product_variants_on_store_product_id"
  end

  create_table "store_products", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", default: "CNY", null: false
    t.text "description"
    t.jsonb "fulfillment_config", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.integer "price_cents", default: 0, null: false
    t.string "product_type", null: false
    t.string "public_id", null: false
    t.integer "purchase_limit"
    t.string "slug", null: false
    t.string "status", default: "draft", null: false
    t.integer "stock"
    t.bigint "store_category_id"
    t.datetime "updated_at", null: false
    t.index ["public_id"], name: "index_store_products_on_public_id", unique: true
    t.index ["slug"], name: "index_store_products_on_slug", unique: true
    t.index ["store_category_id"], name: "index_store_products_on_store_category_id"
  end

  create_table "store_refunds", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.bigint "approved_by_id"
    t.datetime "created_at", null: false
    t.bigint "payment_record_id", null: false
    t.string "reason"
    t.bigint "requested_by_id"
    t.string "status", default: "pending", null: false
    t.bigint "store_order_id", null: false
    t.datetime "updated_at", null: false
    t.index ["approved_by_id"], name: "index_store_refunds_on_approved_by_id"
    t.index ["payment_record_id"], name: "index_store_refunds_on_payment_record_id"
    t.index ["requested_by_id"], name: "index_store_refunds_on_requested_by_id"
    t.index ["store_order_id"], name: "index_store_refunds_on_store_order_id"
  end

  create_table "user_roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "role_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["role_id"], name: "index_user_roles_on_role_id"
    t.index ["user_id", "role_id"], name: "index_user_roles_on_user_id_and_role_id", unique: true
    t.index ["user_id"], name: "index_user_roles_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "ban_expires_at"
    t.text "ban_reason"
    t.datetime "banned_at"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "display_name"
    t.string "email", null: false
    t.datetime "email_verification_sent_at"
    t.string "email_verification_token_digest"
    t.boolean "email_verified", default: false, null: false
    t.datetime "email_verified_at"
    t.integer "failed_login_count", default: 0, null: false
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.string "locale", default: "zh-CN", null: false
    t.datetime "locked_until"
    t.string "password_digest", null: false
    t.datetime "password_reset_sent_at"
    t.string "password_reset_token_digest"
    t.string "public_id", null: false
    t.text "recovery_codes_ciphertext"
    t.boolean "require_totp", default: false, null: false
    t.string "status", default: "active", null: false
    t.string "time_zone", default: "Asia/Shanghai", null: false
    t.boolean "totp_enabled", default: false, null: false
    t.string "totp_secret_ciphertext"
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.index ["deleted_at"], name: "index_users_on_deleted_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["public_id"], name: "index_users_on_public_id", unique: true
    t.index ["status"], name: "index_users_on_status"
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  create_table "website_articles", force: :cascade do |t|
    t.string "article_type", default: "news", null: false
    t.bigint "author_id"
    t.datetime "created_at", null: false
    t.string "public_id", null: false
    t.datetime "published_at"
    t.datetime "scheduled_at"
    t.jsonb "seo", default: {}, null: false
    t.string "slug", null: false
    t.string "status", default: "draft", null: false
    t.text "summary"
    t.string "title", null: false
    t.jsonb "translations", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["article_type", "slug"], name: "index_website_articles_on_article_type_and_slug", unique: true
    t.index ["author_id"], name: "index_website_articles_on_author_id"
    t.index ["public_id"], name: "index_website_articles_on_public_id", unique: true
  end

  create_table "website_blocks", force: :cascade do |t|
    t.string "block_type", null: false
    t.datetime "created_at", null: false
    t.integer "position", default: 0, null: false
    t.jsonb "settings", default: {}, null: false
    t.jsonb "translations", default: {}, null: false
    t.datetime "updated_at", null: false
    t.boolean "visible", default: true, null: false
    t.bigint "website_page_id", null: false
    t.index ["website_page_id", "position"], name: "index_website_blocks_on_website_page_id_and_position"
    t.index ["website_page_id"], name: "index_website_blocks_on_website_page_id"
  end

  create_table "website_nav_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "label", null: false
    t.string "location", default: "header", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.boolean "visible", default: true, null: false
    t.bigint "website_page_id"
    t.index ["website_page_id"], name: "index_website_nav_items_on_website_page_id"
  end

  create_table "website_page_revisions", force: :cascade do |t|
    t.bigint "author_id"
    t.datetime "created_at", null: false
    t.integer "revision_number", null: false
    t.jsonb "snapshot", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "website_page_id", null: false
    t.index ["author_id"], name: "index_website_page_revisions_on_author_id"
    t.index ["website_page_id", "revision_number"], name: "idx_on_website_page_id_revision_number_1396ad78f2", unique: true
    t.index ["website_page_id"], name: "index_website_page_revisions_on_website_page_id"
  end

  create_table "website_pages", force: :cascade do |t|
    t.bigint "author_id"
    t.datetime "created_at", null: false
    t.integer "lock_version", default: 0, null: false
    t.string "page_type", default: "custom", null: false
    t.string "public_id", null: false
    t.datetime "published_at"
    t.datetime "scheduled_at"
    t.jsonb "seo", default: {}, null: false
    t.string "slug", null: false
    t.string "status", default: "draft", null: false
    t.string "title", null: false
    t.jsonb "translations", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "website_theme_id"
    t.index ["author_id"], name: "index_website_pages_on_author_id"
    t.index ["public_id"], name: "index_website_pages_on_public_id", unique: true
    t.index ["slug"], name: "index_website_pages_on_slug", unique: true
    t.index ["status"], name: "index_website_pages_on_status"
    t.index ["website_theme_id"], name: "index_website_pages_on_website_theme_id"
  end

  create_table "website_themes", force: :cascade do |t|
    t.boolean "active", default: false, null: false
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.jsonb "tokens", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_website_themes_on_key", unique: true
  end

  add_foreign_key "audit_logs", "users", column: "actor_id"
  add_foreign_key "forum_mutes", "forum_sections"
  add_foreign_key "forum_mutes", "users"
  add_foreign_key "forum_mutes", "users", column: "created_by_id"
  add_foreign_key "forum_post_edits", "forum_posts"
  add_foreign_key "forum_post_edits", "users", column: "editor_id"
  add_foreign_key "forum_posts", "forum_posts", column: "quoted_post_id"
  add_foreign_key "forum_posts", "forum_topics"
  add_foreign_key "forum_posts", "users"
  add_foreign_key "forum_reactions", "forum_posts"
  add_foreign_key "forum_reactions", "users"
  add_foreign_key "forum_read_states", "forum_topics"
  add_foreign_key "forum_read_states", "users"
  add_foreign_key "forum_reports", "users", column: "reporter_id"
  add_foreign_key "forum_reports", "users", column: "reviewer_id"
  add_foreign_key "forum_sections", "forum_categories"
  add_foreign_key "forum_sections", "forum_sections", column: "parent_id"
  add_foreign_key "forum_subscriptions", "users"
  add_foreign_key "forum_topics", "forum_sections"
  add_foreign_key "forum_topics", "users"
  add_foreign_key "forum_topics", "users", column: "last_post_user_id"
  add_foreign_key "installation_locks", "users", column: "locked_by_id"
  add_foreign_key "minecraft_connector_tasks", "minecraft_servers"
  add_foreign_key "minecraft_connector_tasks", "store_fulfillments"
  add_foreign_key "minecraft_identities", "minecraft_servers"
  add_foreign_key "minecraft_identities", "users"
  add_foreign_key "minecraft_link_codes", "minecraft_servers"
  add_foreign_key "minecraft_link_codes", "users", column: "used_by_id"
  add_foreign_key "minecraft_processed_deliveries", "minecraft_servers"
  add_foreign_key "notification_preferences", "users"
  add_foreign_key "notifications", "users"
  add_foreign_key "payment_attempts", "payment_records"
  add_foreign_key "payment_records", "store_orders"
  add_foreign_key "role_permissions", "permissions"
  add_foreign_key "role_permissions", "roles"
  add_foreign_key "sessions", "users"
  add_foreign_key "store_cart_items", "store_carts"
  add_foreign_key "store_cart_items", "store_product_variants"
  add_foreign_key "store_cart_items", "store_products"
  add_foreign_key "store_carts", "users"
  add_foreign_key "store_fulfillment_attempts", "store_fulfillments"
  add_foreign_key "store_fulfillments", "store_order_items"
  add_foreign_key "store_fulfillments", "store_orders"
  add_foreign_key "store_order_events", "store_orders"
  add_foreign_key "store_order_events", "users", column: "actor_id"
  add_foreign_key "store_order_items", "store_orders"
  add_foreign_key "store_order_items", "store_product_variants"
  add_foreign_key "store_order_items", "store_products"
  add_foreign_key "store_orders", "store_coupons"
  add_foreign_key "store_orders", "users"
  add_foreign_key "store_product_variants", "store_products"
  add_foreign_key "store_products", "store_categories"
  add_foreign_key "store_refunds", "payment_records"
  add_foreign_key "store_refunds", "store_orders"
  add_foreign_key "store_refunds", "users", column: "approved_by_id"
  add_foreign_key "store_refunds", "users", column: "requested_by_id"
  add_foreign_key "user_roles", "roles"
  add_foreign_key "user_roles", "users"
  add_foreign_key "website_articles", "users", column: "author_id"
  add_foreign_key "website_blocks", "website_pages"
  add_foreign_key "website_nav_items", "website_pages"
  add_foreign_key "website_page_revisions", "users", column: "author_id"
  add_foreign_key "website_page_revisions", "website_pages"
  add_foreign_key "website_pages", "users", column: "author_id"
  add_foreign_key "website_pages", "website_themes"
end
