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

ActiveRecord::Schema[8.1].define(version: 2026_08_22_090000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"
  enable_extension "pgcrypto"

  create_table "action_mailbox_inbound_emails", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "message_checksum", null: false
    t.string "message_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "message_checksum"], name: "index_action_mailbox_inbound_emails_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "admin_module_grants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "granted_at", null: false
    t.bigint "granted_by_id"
    t.string "module_key", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["granted_by_id"], name: "index_admin_module_grants_on_granted_by_id"
    t.index ["user_id", "module_key"], name: "index_admin_module_grants_on_user_id_and_module_key", unique: true
    t.index ["user_id"], name: "index_admin_module_grants_on_user_id"
  end

  create_table "api_keys", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.datetime "last_used_at"
    t.string "name", null: false
    t.string "public_id", null: false
    t.datetime "revoked_at"
    t.string "scopes", default: "read", null: false
    t.string "token_digest", null: false
    t.string "token_prefix", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["public_id"], name: "index_api_keys_on_public_id", unique: true
    t.index ["token_digest"], name: "index_api_keys_on_token_digest", unique: true
    t.index ["token_prefix"], name: "index_api_keys_on_token_prefix"
  end

  create_table "audit_logs", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "actor_id"
    t.jsonb "after_state", default: {}, null: false
    t.jsonb "before_state", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.jsonb "metadata", default: {}, null: false
    t.text "reason"
    t.string "request_id", limit: 100
    t.bigint "resource_id"
    t.string "resource_public_id"
    t.string "resource_type"
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.index ["action", "created_at"], name: "index_audit_logs_on_action_and_created_at"
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["actor_id", "created_at"], name: "index_audit_logs_on_actor_id_and_created_at"
    t.index ["actor_id"], name: "index_audit_logs_on_actor_id"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
    t.index ["request_id"], name: "index_audit_logs_on_request_id"
    t.index ["resource_public_id"], name: "index_audit_logs_on_resource_public_id"
    t.index ["resource_type", "resource_id"], name: "index_audit_logs_on_resource_type_and_resource_id"
  end

  create_table "community_custom_bbcodes", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.text "replacement", default: "", null: false
    t.string "sample"
    t.string "tag", null: false
    t.datetime "updated_at", null: false
    t.index ["tag"], name: "index_community_custom_bbcodes_on_tag", unique: true
  end

  create_table "community_forum_pages", force: :cascade do |t|
    t.text "body", default: "", null: false
    t.datetime "created_at", null: false
    t.string "nav_label"
    t.integer "position", default: 0, null: false
    t.boolean "published", default: true, null: false
    t.boolean "show_in_nav", default: false, null: false
    t.string "slug", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["show_in_nav", "position"], name: "index_community_forum_pages_on_show_in_nav_and_position"
    t.index ["slug"], name: "index_community_forum_pages_on_slug", unique: true
  end

  create_table "community_forum_themes", force: :cascade do |t|
    t.string "accent_color"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.boolean "is_default", default: false, null: false
    t.string "name", null: false
    t.string "primary_color"
    t.datetime "updated_at", null: false
    t.index ["is_default"], name: "index_community_forum_themes_on_is_default"
  end

  create_table "community_group_memberships", force: :cascade do |t|
    t.bigint "community_user_group_id", null: false
    t.datetime "created_at", null: false
    t.boolean "is_primary", default: false, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["community_user_group_id"], name: "idx_community_group_memberships_on_group"
    t.index ["user_id", "community_user_group_id"], name: "idx_community_group_memberships_unique", unique: true
    t.index ["user_id"], name: "idx_community_group_memberships_one_primary", unique: true, where: "(is_primary = true)"
  end

  create_table "community_help_articles", force: :cascade do |t|
    t.text "body", default: "", null: false
    t.string "category", default: "general", null: false
    t.datetime "created_at", null: false
    t.integer "position", default: 0, null: false
    t.boolean "published", default: true, null: false
    t.string "slug", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["category", "position"], name: "index_community_help_articles_on_category_and_position"
    t.index ["slug"], name: "index_community_help_articles_on_slug", unique: true
  end

  create_table "community_phrase_overrides", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.string "locale", null: false
    t.datetime "updated_at", null: false
    t.text "value", default: "", null: false
    t.index ["locale", "key"], name: "index_community_phrase_overrides_on_locale_and_key", unique: true
  end

  create_table "community_push_subscriptions", force: :cascade do |t|
    t.string "auth_key", null: false
    t.datetime "created_at", null: false
    t.string "endpoint", null: false
    t.string "p256dh_key", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["endpoint"], name: "index_community_push_subscriptions_on_endpoint", unique: true
    t.index ["user_id"], name: "index_community_push_subscriptions_on_user_id"
  end

  create_table "community_smilies", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "emoji", null: false
    t.integer "position", default: 0, null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_community_smilies_on_code", unique: true
  end

  create_table "community_user_groups", force: :cascade do |t|
    t.string "banner_text"
    t.string "color_hex"
    t.datetime "created_at", null: false
    t.boolean "is_primary_default", default: false, null: false
    t.string "name", null: false
    t.jsonb "permissions", default: [], null: false
    t.integer "priority", default: 0, null: false
    t.datetime "updated_at", null: false
  end

  create_table "data_content_lifecycle_records", force: :cascade do |t|
    t.jsonb "blocker_codes", default: [], null: false
    t.datetime "created_at", null: false
    t.bigint "deleted_by_id"
    t.text "deletion_reason", null: false
    t.datetime "last_evaluated_at"
    t.integer "lock_version", default: 0, null: false
    t.string "public_id", null: false
    t.datetime "purge_after"
    t.integer "purge_attempts", default: 0, null: false
    t.text "purge_reason"
    t.datetime "purged_at"
    t.bigint "purged_by_id"
    t.text "restoration_reason"
    t.datetime "restored_at"
    t.bigint "restored_by_id"
    t.datetime "soft_deleted_at", null: false
    t.string "status", default: "soft_deleted", null: false
    t.bigint "target_id", null: false
    t.jsonb "target_snapshot", default: {}, null: false
    t.string "target_type", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_by_id"], name: "index_data_content_lifecycle_records_on_deleted_by_id"
    t.index ["public_id"], name: "index_data_content_lifecycle_records_on_public_id", unique: true
    t.index ["purged_by_id"], name: "index_data_content_lifecycle_records_on_purged_by_id"
    t.index ["restored_by_id"], name: "index_data_content_lifecycle_records_on_restored_by_id"
    t.index ["status", "purge_after", "id"], name: "idx_data_lifecycle_due"
    t.index ["target_type", "target_id"], name: "idx_data_lifecycle_target", unique: true
    t.check_constraint "purge_attempts >= 0", name: "chk_data_content_lifecycle_attempts"
    t.check_constraint "status::text = ANY (ARRAY['soft_deleted'::character varying::text, 'restored'::character varying::text, 'purged'::character varying::text])", name: "chk_data_content_lifecycle_status"
  end

  create_table "data_retention_holds", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id", null: false
    t.datetime "expires_at"
    t.string "policy_reference"
    t.string "public_id", null: false
    t.text "reason", null: false
    t.text "release_reason"
    t.datetime "released_at"
    t.bigint "released_by_id"
    t.string "status", default: "active", null: false
    t.bigint "target_id", null: false
    t.string "target_type", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_data_retention_holds_on_created_by_id"
    t.index ["public_id"], name: "index_data_retention_holds_on_public_id", unique: true
    t.index ["released_by_id"], name: "index_data_retention_holds_on_released_by_id"
    t.index ["target_type", "target_id", "status"], name: "idx_retention_holds_target_status"
    t.index ["target_type", "target_id"], name: "index_data_retention_holds_on_target"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'released'::character varying::text])", name: "chk_data_retention_holds_status"
  end

  create_table "data_retention_policies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "legal_hold_supported", default: true, null: false
    t.boolean "moderator_restorable", default: true, null: false
    t.text "notes"
    t.string "resource_type", null: false
    t.integer "retention_days"
    t.datetime "updated_at", null: false
    t.boolean "user_deletable", default: true, null: false
    t.index ["resource_type"], name: "index_data_retention_policies_on_resource_type", unique: true
  end

  create_table "developer_mode_runtime_states", force: :cascade do |t|
    t.string "configuration_digest", null: false
    t.jsonb "configuration_summary", default: {}, null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: false, null: false
    t.datetime "observed_at", null: false
    t.string "profile"
    t.datetime "updated_at", null: false
  end

  create_table "email_bans", force: :cascade do |t|
    t.bigint "banned_by_id"
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "pattern", null: false
    t.text "reason"
    t.datetime "updated_at", null: false
    t.index ["banned_by_id"], name: "index_email_bans_on_banned_by_id"
    t.index ["pattern"], name: "index_email_bans_on_pattern", unique: true
  end

  create_table "forum_badges", force: :cascade do |t|
    t.string "color", default: "#6366f1"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "grant_rule", default: "manual", null: false
    t.integer "grant_threshold", default: 0
    t.string "grouping", default: "general", null: false
    t.string "icon", default: "🏅", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.string "tier", default: "bronze", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_forum_badges_on_slug", unique: true
  end

  create_table "forum_bookmarks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "forum_post_id"
    t.bigint "forum_topic_id", null: false
    t.string "label"
    t.text "note"
    t.datetime "remind_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["forum_post_id"], name: "index_forum_bookmarks_on_forum_post_id"
    t.index ["forum_topic_id"], name: "index_forum_bookmarks_on_forum_topic_id"
    t.index ["remind_at"], name: "index_forum_bookmarks_on_remind_at", where: "(remind_at IS NOT NULL)"
    t.index ["user_id", "forum_post_id"], name: "index_forum_bookmarks_on_user_id_and_forum_post_id", unique: true, where: "(forum_post_id IS NOT NULL)"
    t.index ["user_id", "forum_topic_id"], name: "index_forum_bookmarks_on_user_topic_without_post", unique: true, where: "(forum_post_id IS NULL)"
    t.index ["user_id", "label"], name: "index_forum_bookmarks_on_user_id_and_label"
    t.index ["user_id"], name: "index_forum_bookmarks_on_user_id"
  end

  create_table "forum_canned_responses", force: :cascade do |t|
    t.bigint "author_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_forum_canned_responses_on_author_id"
  end

  create_table "forum_categories", force: :cascade do |t|
    t.string "color_hex"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "icon"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.jsonb "seo", default: {}, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_forum_categories_on_slug", unique: true
  end

  create_table "forum_censored_words", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "replacement", default: "***", null: false
    t.datetime "updated_at", null: false
    t.string "word", null: false
    t.index ["word"], name: "index_forum_censored_words_on_word", unique: true
  end

  create_table "forum_check_ins", force: :cascade do |t|
    t.date "checked_on", null: false
    t.datetime "created_at", null: false
    t.integer "points_awarded", default: 0, null: false
    t.integer "streak", default: 1, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "checked_on"], name: "idx_forum_check_ins_user_date", unique: true
  end

  create_table "forum_content_requests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "forum_post_id"
    t.bigint "forum_topic_id"
    t.string "key_digest", limit: 64, null: false
    t.string "operation", limit: 32, null: false
    t.string "request_fingerprint", limit: 64, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["forum_post_id"], name: "index_forum_content_requests_on_forum_post_id"
    t.index ["forum_topic_id"], name: "index_forum_content_requests_on_forum_topic_id"
    t.index ["user_id", "operation", "key_digest"], name: "idx_forum_content_requests_idempotency", unique: true
    t.index ["user_id"], name: "index_forum_content_requests_on_user_id"
    t.check_constraint "operation::text = ANY (ARRAY['topic.create'::character varying::text, 'post.create'::character varying::text])", name: "chk_forum_content_requests_operation"
  end

  create_table "forum_conversation_participants", force: :cascade do |t|
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.bigint "forum_conversation_id", null: false
    t.string "label"
    t.datetime "last_read_at"
    t.datetime "muted_at"
    t.datetime "starred_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["forum_conversation_id", "user_id"], name: "idx_forum_conv_participants_unique", unique: true
    t.index ["forum_conversation_id"], name: "index_forum_conversation_participants_on_forum_conversation_id"
    t.index ["muted_at"], name: "index_forum_conversation_participants_on_muted_at"
    t.index ["user_id"], name: "index_forum_conversation_participants_on_user_id"
  end

  create_table "forum_conversations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "creator_id"
    t.boolean "invites_locked", default: false, null: false
    t.boolean "is_group", default: false, null: false
    t.datetime "last_message_at"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_forum_conversations_on_creator_id"
  end

  create_table "forum_email_reply_addresses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "forum_topic_id", null: false
    t.datetime "last_used_at"
    t.string "purpose", null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["forum_topic_id"], name: "index_forum_email_reply_addresses_on_forum_topic_id"
    t.index ["token_digest"], name: "index_forum_email_reply_addresses_on_token_digest", unique: true
    t.index ["user_id", "forum_topic_id", "expires_at"], name: "idx_forum_email_reply_addresses_binding"
    t.index ["user_id"], name: "index_forum_email_reply_addresses_on_user_id"
  end

  create_table "forum_email_reply_deliveries", force: :cascade do |t|
    t.bigint "action_mailbox_inbound_email_id"
    t.datetime "created_at", null: false
    t.bigint "forum_email_reply_address_id"
    t.bigint "forum_post_id"
    t.string "message_id_digest", null: false
    t.string "rejection_reason"
    t.string "status", default: "processing", null: false
    t.datetime "updated_at", null: false
    t.index ["action_mailbox_inbound_email_id"], name: "idx_forum_email_replies_on_inbound", unique: true
    t.index ["forum_email_reply_address_id"], name: "idx_forum_email_replies_on_address"
    t.index ["forum_post_id"], name: "idx_forum_email_replies_on_post"
    t.index ["message_id_digest"], name: "idx_forum_email_replies_on_message_id", unique: true
  end

  create_table "forum_event_webhook_deliveries", force: :cascade do |t|
    t.integer "attempt_count", default: 1, null: false
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.bigint "forum_post_id"
    t.bigint "forum_topic_id"
    t.jsonb "request_payload", default: {}
    t.text "response_body"
    t.integer "response_code"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["created_at"], name: "index_forum_event_webhook_deliveries_on_created_at"
    t.index ["event_type"], name: "index_forum_event_webhook_deliveries_on_event_type"
    t.index ["forum_post_id"], name: "index_forum_event_webhook_deliveries_on_forum_post_id"
    t.index ["forum_topic_id"], name: "index_forum_event_webhook_deliveries_on_forum_topic_id"
    t.index ["status"], name: "index_forum_event_webhook_deliveries_on_status"
  end

  create_table "forum_message_drafts", force: :cascade do |t|
    t.jsonb "attachment_ids", default: [], null: false
    t.text "body", default: "", null: false
    t.datetime "created_at", null: false
    t.bigint "forum_conversation_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["forum_conversation_id"], name: "index_forum_message_drafts_on_forum_conversation_id"
    t.index ["user_id", "forum_conversation_id"], name: "index_forum_message_drafts_on_user_and_conversation", unique: true
  end

  create_table "forum_message_revision_backfill_queue", id: false, force: :cascade do |t|
    t.string "body_digest", limit: 64, null: false
    t.bigint "forum_message_id", null: false
    t.datetime "queued_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.integer "revision", null: false
    t.index ["forum_message_id", "revision"], name: "idx_forum_message_revision_backfill_queue_unique", unique: true
    t.check_constraint "body_digest::text ~ '^[0-9a-f]{64}$'::text", name: "forum_message_revision_queue_digest_format"
    t.check_constraint "revision > 0", name: "forum_message_revision_queue_positive_revision"
  end

  create_table "forum_message_revisions", force: :cascade do |t|
    t.string "content_digest", limit: 64, null: false
    t.datetime "created_at", null: false
    t.bigint "editor_id", null: false
    t.text "encrypted_body", null: false
    t.bigint "forum_message_id", null: false
    t.integer "revision", null: false
    t.index ["editor_id"], name: "index_forum_message_revisions_on_editor_id"
    t.index ["forum_message_id", "revision"], name: "idx_forum_message_revisions_unique", unique: true
    t.index ["forum_message_id"], name: "index_forum_message_revisions_on_forum_message_id"
    t.check_constraint "content_digest::text ~ '^[0-9a-f]{64}$'::text", name: "forum_message_revisions_digest_format"
    t.check_constraint "revision > 0", name: "forum_message_revisions_positive_revision"
  end

  create_table "forum_messages", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.datetime "edited_at"
    t.bigint "forum_conversation_id", null: false
    t.integer "revision", default: 1, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["deleted_at"], name: "index_forum_messages_on_deleted_at"
    t.index ["forum_conversation_id", "created_at"], name: "index_forum_messages_on_forum_conversation_id_and_created_at"
    t.index ["forum_conversation_id"], name: "index_forum_messages_on_forum_conversation_id"
    t.index ["user_id"], name: "index_forum_messages_on_user_id"
    t.check_constraint "revision > 0", name: "forum_messages_positive_revision"
  end

  create_table "forum_moderation_case_notes", force: :cascade do |t|
    t.bigint "author_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.bigint "moderation_case_id", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_forum_moderation_case_notes_on_author_id"
    t.index ["moderation_case_id", "created_at"], name: "idx_forum_moderation_case_notes_timeline"
  end

  create_table "forum_moderation_cases", force: :cascade do |t|
    t.bigint "assignee_id"
    t.datetime "claimed_at"
    t.datetime "created_at", null: false
    t.bigint "forum_section_id"
    t.string "last_action"
    t.text "last_reason"
    t.integer "lock_version", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "priority", default: "normal", null: false
    t.datetime "resolved_at"
    t.string "risk_level", default: "medium", null: false
    t.bigint "source_id", null: false
    t.string "source_kind", null: false
    t.string "source_type", null: false
    t.datetime "source_updated_at", null: false
    t.string "status", default: "open", null: false
    t.text "summary", default: "", null: false
    t.bigint "target_user_id"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["assignee_id", "status"], name: "idx_forum_moderation_cases_assignee"
    t.index ["assignee_id"], name: "index_forum_moderation_cases_on_assignee_id"
    t.index ["forum_section_id", "status"], name: "idx_forum_moderation_cases_section"
    t.index ["forum_section_id"], name: "index_forum_moderation_cases_on_forum_section_id"
    t.index ["source_kind", "source_updated_at"], name: "idx_forum_moderation_cases_source_kind"
    t.index ["source_type", "source_id"], name: "idx_forum_moderation_cases_source", unique: true
    t.index ["status", "priority", "risk_level", "updated_at"], name: "idx_forum_moderation_cases_queue"
    t.index ["target_user_id"], name: "index_forum_moderation_cases_on_target_user_id"
    t.check_constraint "priority::text = ANY (ARRAY['low'::character varying::text, 'normal'::character varying::text, 'high'::character varying::text, 'critical'::character varying::text])", name: "forum_moderation_cases_priority"
    t.check_constraint "risk_level::text = ANY (ARRAY['low'::character varying::text, 'medium'::character varying::text, 'high'::character varying::text, 'critical'::character varying::text])", name: "forum_moderation_cases_risk"
    t.check_constraint "source_kind::text = ANY (ARRAY['pending_topic'::character varying::text, 'pending_post'::character varying::text, 'report'::character varying::text, 'spam_hit'::character varying::text, 'quarantined_attachment'::character varying::text, 'user_risk'::character varying::text])", name: "forum_moderation_cases_source_kind"
    t.check_constraint "status::text = ANY (ARRAY['open'::character varying::text, 'claimed'::character varying::text, 'resolved'::character varying::text, 'dismissed'::character varying::text, 'actioned'::character varying::text, 'stale'::character varying::text])", name: "forum_moderation_cases_status"
  end

  create_table "forum_moderation_operations", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "actor_id", null: false
    t.string "authorization_digest", null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.text "reason", null: false
    t.string "request_fingerprint", null: false
    t.string "request_id", null: false
    t.jsonb "result_snapshot", default: [], null: false
    t.jsonb "target_snapshot", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id", "created_at"], name: "idx_forum_moderation_operations_actor"
    t.index ["actor_id"], name: "index_forum_moderation_operations_on_actor_id"
    t.index ["authorization_digest"], name: "index_forum_moderation_operations_on_authorization_digest", unique: true
    t.index ["request_id"], name: "index_forum_moderation_operations_on_request_id", unique: true
    t.check_constraint "char_length(request_fingerprint::text) = 64 AND char_length(authorization_digest::text) = 64", name: "forum_moderation_operations_digests"
    t.check_constraint "request_id::text ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'::text", name: "forum_moderation_operations_request_id"
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

  create_table "forum_notices", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "audience", default: "everyone", null: false
    t.datetime "created_at", null: false
    t.boolean "dismissible", default: true, null: false
    t.datetime "ends_at"
    t.integer "max_trust_level"
    t.text "message", null: false
    t.integer "min_trust_level"
    t.integer "position", default: 0, null: false
    t.datetime "starts_at"
    t.string "style", default: "info", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["active", "position"], name: "index_forum_notices_on_active_and_position"
  end

  create_table "forum_point_accounts", force: :cascade do |t|
    t.integer "balance", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "points", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["currency"], name: "index_forum_point_accounts_on_currency"
    t.index ["user_id", "currency"], name: "idx_forum_point_accounts_user_currency", unique: true
  end

  create_table "forum_point_transactions", force: :cascade do |t|
    t.integer "amount", null: false
    t.integer "balance_after", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "points", null: false
    t.string "dedupe_token"
    t.bigint "forum_point_account_id", null: false
    t.string "reason", null: false
    t.bigint "source_id"
    t.string "source_type"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["dedupe_token"], name: "idx_forum_point_tx_dedupe_token", unique: true, where: "(dedupe_token IS NOT NULL)"
    t.index ["forum_point_account_id"], name: "idx_forum_point_tx_account"
    t.index ["source_type", "source_id"], name: "idx_forum_point_tx_source"
    t.index ["user_id", "created_at"], name: "idx_forum_point_tx_user_created"
    t.index ["user_id", "currency", "reason", "source_type", "source_id"], name: "idx_forum_point_tx_idempotency", unique: true, where: "(source_id IS NOT NULL)"
  end

  create_table "forum_poll_votes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "forum_poll_id", null: false
    t.integer "option_index", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["forum_poll_id", "user_id", "option_index"], name: "index_forum_poll_votes_on_poll_user_option", unique: true
    t.index ["forum_poll_id"], name: "index_forum_poll_votes_on_forum_poll_id"
    t.index ["user_id"], name: "index_forum_poll_votes_on_user_id"
  end

  create_table "forum_polls", force: :cascade do |t|
    t.boolean "anonymous", default: false, null: false
    t.datetime "closes_at"
    t.datetime "created_at", null: false
    t.bigint "forum_topic_id", null: false
    t.boolean "hide_results_until_vote", default: false, null: false
    t.integer "max_choices", default: 1, null: false
    t.boolean "multiple_choice", default: false, null: false
    t.jsonb "options", default: [], null: false
    t.string "question", null: false
    t.datetime "updated_at", null: false
    t.index ["forum_topic_id"], name: "index_forum_polls_on_forum_topic_id", unique: true
  end

  create_table "forum_post_attachments", force: :cascade do |t|
    t.bigint "byte_size", default: 0, null: false
    t.string "content_type"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.integer "download_count", default: 0, null: false
    t.string "filename", null: false
    t.bigint "forum_message_id"
    t.bigint "forum_post_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["deleted_at"], name: "index_forum_post_attachments_on_deleted_at"
    t.index ["forum_message_id"], name: "index_forum_post_attachments_on_forum_message_id"
    t.index ["forum_post_id"], name: "index_forum_post_attachments_on_forum_post_id"
    t.index ["user_id", "forum_post_id"], name: "index_forum_post_attachments_on_user_id_and_forum_post_id"
    t.index ["user_id"], name: "index_forum_post_attachments_on_user_id"
    t.check_constraint "NOT (forum_post_id IS NOT NULL AND forum_message_id IS NOT NULL)", name: "forum_post_attachments_single_parent"
  end

  create_table "forum_post_edits", force: :cascade do |t|
    t.text "body_after"
    t.text "body_before"
    t.datetime "created_at", null: false
    t.bigint "editor_id", null: false
    t.bigint "forum_post_id", null: false
    t.string "reason"
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
    t.bigint "parent_post_id"
    t.string "post_type", default: "regular", null: false
    t.bigint "quoted_post_id"
    t.integer "revision", default: 1, null: false
    t.text "staff_notice"
    t.string "status", default: "published", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.boolean "wiki", default: false, null: false
    t.index "to_tsvector('simple'::regconfig, COALESCE(body, ''::text))", name: "index_forum_posts_on_body_tsvector", using: :gin
    t.index ["created_at", "forum_topic_id"], name: "idx_forum_posts_top_window", where: "((deleted_at IS NULL) AND ((status)::text = 'published'::text) AND ((post_type)::text = 'regular'::text))"
    t.index ["deleted_at"], name: "index_forum_posts_on_deleted_at"
    t.index ["forum_topic_id", "floor_number"], name: "idx_forum_posts_unread_floor", where: "((deleted_at IS NULL) AND ((status)::text = 'published'::text) AND ((post_type)::text = 'regular'::text))"
    t.index ["forum_topic_id", "floor_number"], name: "index_forum_posts_on_forum_topic_id_and_floor_number", unique: true
    t.index ["forum_topic_id"], name: "index_forum_posts_on_forum_topic_id"
    t.index ["parent_post_id"], name: "index_forum_posts_on_parent_post_id"
    t.index ["quoted_post_id"], name: "index_forum_posts_on_quoted_post_id"
    t.index ["user_id"], name: "index_forum_posts_on_user_id"
    t.check_constraint "revision > 0", name: "forum_posts_positive_revision"
  end

  create_table "forum_profile_post_comments", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.datetime "edited_at"
    t.bigint "profile_post_id", null: false
    t.integer "revision", default: 1, null: false
    t.string "status", default: "published", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["profile_post_id", "created_at"], name: "idx_on_profile_post_id_created_at_786d3823a2"
    t.index ["user_id"], name: "index_forum_profile_post_comments_on_user_id"
    t.check_constraint "revision > 0", name: "forum_profile_post_comments_positive_revision"
  end

  create_table "forum_profile_posts", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.datetime "edited_at"
    t.bigint "profile_user_id", null: false
    t.integer "revision", default: 1, null: false
    t.string "status", default: "published", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["profile_user_id", "created_at"], name: "index_forum_profile_posts_on_profile_user_id_and_created_at"
    t.index ["user_id"], name: "index_forum_profile_posts_on_user_id"
    t.check_constraint "revision > 0", name: "forum_profile_posts_positive_revision"
  end

  create_table "forum_reaction_types", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "emoji", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "score", default: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["active", "position"], name: "index_forum_reaction_types_on_active_and_position"
    t.index ["emoji"], name: "index_forum_reaction_types_on_emoji", unique: true
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

  create_table "forum_reply_drafts", force: :cascade do |t|
    t.jsonb "attachment_ids", default: [], null: false
    t.text "body", default: "", null: false
    t.datetime "created_at", null: false
    t.bigint "forum_topic_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["forum_topic_id"], name: "index_forum_reply_drafts_on_forum_topic_id"
    t.index ["user_id", "forum_topic_id"], name: "index_forum_reply_drafts_on_user_id_and_forum_topic_id", unique: true
    t.index ["user_id"], name: "index_forum_reply_drafts_on_user_id"
  end

  create_table "forum_report_evidences", force: :cascade do |t|
    t.datetime "captured_at", null: false
    t.string "content_digest", limit: 64, null: false
    t.datetime "created_at", null: false
    t.text "encrypted_snapshot", null: false
    t.bigint "forum_report_id", null: false
    t.bigint "subject_id", null: false
    t.integer "subject_revision", default: 1, null: false
    t.string "subject_type", null: false
    t.datetime "updated_at", null: false
    t.index ["forum_report_id"], name: "index_forum_report_evidences_on_forum_report_id", unique: true
    t.index ["subject_type", "subject_id"], name: "idx_forum_report_evidences_subject"
    t.check_constraint "content_digest::text ~ '^[0-9a-f]{64}$'::text", name: "forum_report_evidences_digest_format"
    t.check_constraint "subject_revision > 0", name: "forum_report_evidences_positive_revision"
  end

  create_table "forum_reports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "dedupe_key", limit: 64
    t.text "reason", null: false
    t.string "reason_code"
    t.bigint "reportable_id", null: false
    t.string "reportable_type", null: false
    t.bigint "reporter_id", null: false
    t.text "review_note"
    t.datetime "reviewed_at"
    t.bigint "reviewer_id"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["dedupe_key"], name: "idx_forum_reports_pending_dedupe", unique: true, where: "((dedupe_key IS NOT NULL) AND ((status)::text = 'pending'::text))"
    t.index ["reason_code"], name: "index_forum_reports_on_reason_code"
    t.index ["reportable_type", "reportable_id"], name: "index_forum_reports_on_reportable_type_and_reportable_id"
    t.index ["reporter_id"], name: "index_forum_reports_on_reporter_id"
    t.index ["reviewer_id"], name: "index_forum_reports_on_reviewer_id"
    t.check_constraint "dedupe_key IS NULL OR dedupe_key::text ~ '^[0-9a-f]{64}$'::text", name: "forum_reports_dedupe_key_format"
  end

  create_table "forum_saved_search_webhook_deliveries", force: :cascade do |t|
    t.integer "attempt_count", default: 1, null: false
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.jsonb "request_payload", default: {}, null: false
    t.text "response_body"
    t.integer "response_code"
    t.bigint "saved_search_id"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.string "url", limit: 2048, null: false
    t.index ["created_at"], name: "index_forum_saved_search_webhook_deliveries_on_created_at"
    t.index ["saved_search_id"], name: "index_forum_saved_search_webhook_deliveries_on_saved_search_id"
  end

  create_table "forum_saved_searches", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "filters", default: {}, null: false
    t.datetime "last_notified_at"
    t.string "name", null: false
    t.boolean "notify_daily", default: false, null: false
    t.boolean "notify_in_app", default: true, null: false
    t.text "query", default: "", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "webhook_url"
    t.index ["user_id", "created_at"], name: "index_forum_saved_searches_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_forum_saved_searches_on_user_id"
  end

  create_table "forum_search_histories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "filters", default: {}, null: false
    t.string "fingerprint"
    t.string "query", default: "", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "created_at"], name: "index_forum_search_histories_on_user_id_and_created_at"
    t.index ["user_id", "fingerprint"], name: "index_forum_search_histories_on_user_id_and_fingerprint", unique: true
    t.index ["user_id"], name: "index_forum_search_histories_on_user_id"
  end

  create_table "forum_section_moderators", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "forum_section_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["forum_section_id", "user_id"], name: "index_forum_section_moderators_on_forum_section_id_and_user_id", unique: true
    t.index ["forum_section_id"], name: "index_forum_section_moderators_on_forum_section_id"
    t.index ["user_id"], name: "index_forum_section_moderators_on_user_id"
  end

  create_table "forum_section_mutes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "forum_section_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["forum_section_id"], name: "index_forum_section_mutes_on_forum_section_id"
    t.index ["user_id", "forum_section_id"], name: "index_forum_section_mutes_on_user_id_and_forum_section_id", unique: true
    t.index ["user_id"], name: "index_forum_section_mutes_on_user_id"
  end

  create_table "forum_sections", force: :cascade do |t|
    t.jsonb "allowed_tag_ids", default: [], null: false
    t.datetime "archived_at"
    t.bigint "archived_by_id"
    t.text "archived_reason"
    t.text "banner_text"
    t.string "color_hex"
    t.datetime "created_at", null: false
    t.string "default_notification_level", default: "watching", null: false
    t.jsonb "default_tag_ids", default: [], null: false
    t.text "description"
    t.bigint "forum_category_id", null: false
    t.string "icon"
    t.string "link_label"
    t.string "link_url"
    t.boolean "login_required", default: false, null: false
    t.integer "min_trust_level_create", default: 0, null: false
    t.integer "min_trust_level_reply", default: 0, null: false
    t.string "name", null: false
    t.bigint "parent_id"
    t.jsonb "permissions", default: {}, null: false
    t.integer "position", default: 0, null: false
    t.boolean "prefix_required", default: false, null: false
    t.jsonb "prefixes", default: [], null: false
    t.boolean "read_only", default: false, null: false
    t.jsonb "required_tag_group_ids", default: [], null: false
    t.jsonb "required_tag_ids", default: [], null: false
    t.jsonb "seo", default: {}, null: false
    t.string "slug", null: false
    t.text "topic_template"
    t.datetime "updated_at", null: false
    t.index ["archived_at", "position"], name: "index_forum_sections_on_archived_at_and_position"
    t.index ["archived_by_id"], name: "index_forum_sections_on_archived_by_id"
    t.index ["forum_category_id", "slug"], name: "index_forum_sections_on_forum_category_id_and_slug", unique: true
    t.index ["forum_category_id"], name: "index_forum_sections_on_forum_category_id"
    t.index ["name", "slug"], name: "idx_forum_sections_suggest_names_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["parent_id"], name: "index_forum_sections_on_parent_id"
  end

  create_table "forum_staff_notes", force: :cascade do |t|
    t.bigint "author_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["author_id"], name: "index_forum_staff_notes_on_author_id"
    t.index ["user_id"], name: "index_forum_staff_notes_on_user_id"
  end

  create_table "forum_subscriptions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "notification_level", default: "watching", null: false
    t.bigint "subscribable_id", null: false
    t.string "subscribable_type", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "subscribable_type", "subscribable_id"], name: "idx_on_user_id_subscribable_type_subscribable_id_8ef4ba5a1f", unique: true
    t.index ["user_id"], name: "index_forum_subscriptions_on_user_id"
  end

  create_table "forum_tag_group_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "forum_tag_group_id", null: false
    t.bigint "forum_tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["forum_tag_group_id", "forum_tag_id"], name: "idx_tag_group_membership_unique", unique: true
    t.index ["forum_tag_group_id"], name: "index_forum_tag_group_memberships_on_forum_tag_group_id"
    t.index ["forum_tag_id"], name: "index_forum_tag_group_memberships_on_forum_tag_id"
  end

  create_table "forum_tag_groups", force: :cascade do |t|
    t.string "color_hex"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.boolean "one_per_topic", default: false, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_forum_tag_groups_on_slug", unique: true
  end

  create_table "forum_tags", force: :cascade do |t|
    t.bigint "canonical_tag_id"
    t.string "color_hex"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.string "slug", null: false
    t.boolean "staff_only", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["canonical_tag_id"], name: "index_forum_tags_on_canonical_tag_id"
    t.index ["name", "slug"], name: "idx_forum_tags_suggest_names_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["slug"], name: "index_forum_tags_on_slug", unique: true
  end

  create_table "forum_topic_field_definitions", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.text "choices"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "display_location", default: "before_message", null: false
    t.boolean "editable_by_user", default: true, null: false
    t.jsonb "editable_group_ids", default: [], null: false
    t.string "field_type", default: "text", null: false
    t.string "key", null: false
    t.string "label", null: false
    t.string "owner_plugin_id"
    t.boolean "required", default: false, null: false
    t.jsonb "section_ids", default: [], null: false
    t.integer "sort_order", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["active", "sort_order"], name: "index_forum_topic_field_definitions_on_active_and_sort_order"
    t.index ["key"], name: "index_forum_topic_field_definitions_on_key", unique: true
    t.index ["owner_plugin_id"], name: "index_forum_topic_field_definitions_on_owner_plugin_id"
  end

  create_table "forum_topic_field_values", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "forum_topic_field_definition_id", null: false
    t.bigint "forum_topic_id", null: false
    t.datetime "updated_at", null: false
    t.text "value", null: false
    t.index ["forum_topic_field_definition_id"], name: "idx_on_forum_topic_field_definition_id_c7ed2b10e6"
    t.index ["forum_topic_id", "forum_topic_field_definition_id"], name: "idx_forum_topic_field_values_unique", unique: true
    t.index ["forum_topic_id"], name: "index_forum_topic_field_values_on_forum_topic_id"
  end

  create_table "forum_topic_invites", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "forum_topic_id", null: false
    t.bigint "invited_by_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["forum_topic_id", "user_id"], name: "index_forum_topic_invites_on_forum_topic_id_and_user_id", unique: true
    t.index ["forum_topic_id"], name: "index_forum_topic_invites_on_forum_topic_id"
    t.index ["invited_by_id"], name: "index_forum_topic_invites_on_invited_by_id"
    t.index ["user_id"], name: "index_forum_topic_invites_on_user_id"
  end

  create_table "forum_topic_mutes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "forum_topic_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["forum_topic_id"], name: "index_forum_topic_mutes_on_forum_topic_id"
    t.index ["user_id", "forum_topic_id"], name: "index_forum_topic_mutes_on_user_id_and_forum_topic_id", unique: true
    t.index ["user_id"], name: "index_forum_topic_mutes_on_user_id"
  end

  create_table "forum_topic_reply_bans", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id", null: false
    t.datetime "expires_at"
    t.bigint "forum_topic_id", null: false
    t.text "reason"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["created_by_id"], name: "index_forum_topic_reply_bans_on_created_by_id"
    t.index ["forum_topic_id", "user_id"], name: "idx_topic_reply_bans_unique", unique: true
    t.index ["forum_topic_id"], name: "index_forum_topic_reply_bans_on_forum_topic_id"
    t.index ["user_id"], name: "index_forum_topic_reply_bans_on_user_id"
  end

  create_table "forum_topic_staff_notes", force: :cascade do |t|
    t.bigint "author_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.bigint "forum_topic_id", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_forum_topic_staff_notes_on_author_id"
    t.index ["forum_topic_id"], name: "index_forum_topic_staff_notes_on_forum_topic_id"
  end

  create_table "forum_topic_tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "forum_tag_id", null: false
    t.bigint "forum_topic_id", null: false
    t.datetime "updated_at", null: false
    t.index ["forum_tag_id"], name: "index_forum_topic_tags_on_forum_tag_id"
    t.index ["forum_topic_id", "forum_tag_id"], name: "index_forum_topic_tags_on_forum_topic_id_and_forum_tag_id", unique: true
    t.index ["forum_topic_id"], name: "index_forum_topic_tags_on_forum_topic_id"
  end

  create_table "forum_topics", force: :cascade do |t|
    t.datetime "archived_at"
    t.bigint "assigned_to_id"
    t.datetime "auto_archive_at"
    t.datetime "auto_bump_at"
    t.datetime "auto_close_at"
    t.datetime "auto_open_at"
    t.datetime "bumped_at"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.boolean "featured", default: false, null: false
    t.bigint "forum_section_id", null: false
    t.boolean "global_announcement", default: false, null: false
    t.bigint "last_post_user_id"
    t.datetime "last_posted_at"
    t.string "lock_reason"
    t.boolean "locked", default: false, null: false
    t.boolean "pinned", default: false, null: false
    t.datetime "pinned_until"
    t.string "prefix"
    t.string "public_id", null: false
    t.bigint "redirect_to_topic_id"
    t.integer "replies_count", default: 0, null: false
    t.datetime "scheduled_at"
    t.integer "slow_mode_seconds"
    t.bigint "solved_post_id"
    t.bigint "source_post_id"
    t.string "status", default: "published", null: false
    t.string "title", null: false
    t.boolean "unlisted", default: false, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "views_count", default: 0, null: false
    t.boolean "wiki", default: false, null: false
    t.index "to_tsvector('simple'::regconfig, (COALESCE(title, ''::character varying))::text)", name: "index_forum_topics_on_title_tsvector", using: :gin
    t.index ["archived_at"], name: "index_forum_topics_on_archived_at"
    t.index ["assigned_to_id"], name: "index_forum_topics_on_assigned_to_id"
    t.index ["auto_archive_at"], name: "index_forum_topics_on_auto_archive_at"
    t.index ["auto_bump_at"], name: "index_forum_topics_on_auto_bump_at"
    t.index ["auto_close_at"], name: "index_forum_topics_on_auto_close_at"
    t.index ["auto_open_at"], name: "index_forum_topics_on_auto_open_at"
    t.index ["deleted_at"], name: "index_forum_topics_on_deleted_at"
    t.index ["forum_section_id", "last_posted_at"], name: "index_forum_topics_on_forum_section_id_and_last_posted_at"
    t.index ["forum_section_id"], name: "index_forum_topics_on_forum_section_id"
    t.index ["global_announcement"], name: "index_forum_topics_on_global_announcement", where: "(global_announcement = true)"
    t.index ["last_post_user_id"], name: "index_forum_topics_on_last_post_user_id"
    t.index ["pinned_until"], name: "index_forum_topics_on_pinned_until"
    t.index ["public_id"], name: "index_forum_topics_on_public_id", unique: true
    t.index ["redirect_to_topic_id"], name: "index_forum_topics_on_redirect_to_topic_id"
    t.index ["scheduled_at"], name: "index_forum_topics_on_scheduled_at"
    t.index ["solved_post_id"], name: "index_forum_topics_on_solved_post_id"
    t.index ["source_post_id"], name: "index_forum_topics_on_source_post_id"
    t.index ["title"], name: "idx_forum_topics_suggest_title_trgm", opclass: :gin_trgm_ops, where: "((deleted_at IS NULL) AND ((status)::text = 'published'::text) AND (unlisted = false) AND (archived_at IS NULL))", using: :gin
    t.index ["user_id"], name: "index_forum_topics_on_user_id"
  end

  create_table "forum_unread_filter_presets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "filters", default: {}, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "created_at"], name: "index_forum_unread_filter_presets_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_forum_unread_filter_presets_on_user_id"
  end

  create_table "forum_uploads", force: :cascade do |t|
    t.bigint "active_storage_blob_id"
    t.bigint "byte_size", null: false
    t.datetime "cleaned_at"
    t.integer "cleanup_attempts", default: 0, null: false
    t.string "cleanup_error_code"
    t.text "cleanup_error_message"
    t.datetime "cleanup_started_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.bigint "forum_post_attachment_id"
    t.bigint "forum_post_id"
    t.string "kind", null: false
    t.string "manual_review_file_sha256"
    t.datetime "manual_review_revoked_at"
    t.bigint "manual_review_revoked_by_id"
    t.string "manual_review_source_result_code"
    t.string "manual_review_status", default: "none", null: false
    t.integer "manual_review_version", default: 0, null: false
    t.datetime "manual_reviewed_at"
    t.bigint "manual_reviewed_by_id"
    t.datetime "next_scan_at"
    t.string "public_id", null: false
    t.datetime "quarantined_at"
    t.integer "scan_attempts", default: 0, null: false
    t.text "scan_error_message"
    t.string "scan_result_code"
    t.datetime "scan_started_at"
    t.string "scan_status", default: "pending", null: false
    t.datetime "scanned_at"
    t.string "scanner"
    t.string "status", default: "reserved", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["active_storage_blob_id"], name: "index_forum_uploads_on_active_storage_blob_id", unique: true
    t.index ["forum_post_attachment_id"], name: "index_forum_uploads_on_forum_post_attachment_id", unique: true
    t.index ["forum_post_id"], name: "index_forum_uploads_on_forum_post_id"
    t.index ["kind", "status"], name: "index_forum_uploads_on_kind_and_status"
    t.index ["manual_review_revoked_by_id"], name: "index_forum_uploads_on_manual_review_revoked_by_id"
    t.index ["manual_review_status"], name: "index_forum_uploads_on_manual_review_status"
    t.index ["manual_reviewed_by_id"], name: "index_forum_uploads_on_manual_reviewed_by_id"
    t.index ["public_id"], name: "index_forum_uploads_on_public_id", unique: true
    t.index ["quarantined_at"], name: "index_forum_uploads_on_quarantined_at"
    t.index ["scan_status", "next_scan_at"], name: "idx_forum_uploads_scan_due"
    t.index ["status", "expires_at"], name: "index_forum_uploads_on_status_and_expires_at"
    t.index ["user_id", "status"], name: "index_forum_uploads_on_user_id_and_status"
    t.index ["user_id"], name: "index_forum_uploads_on_user_id"
    t.check_constraint "byte_size > 0", name: "forum_uploads_positive_byte_size"
    t.check_constraint "kind::text = ANY (ARRAY['inline_image'::character varying::text, 'post_attachment'::character varying::text])", name: "forum_uploads_valid_kind"
    t.check_constraint "manual_review_status::text = ANY (ARRAY['none'::character varying::text, 'released'::character varying::text, 'revoked'::character varying::text])", name: "forum_uploads_valid_manual_review_status"
    t.check_constraint "manual_review_version >= 0", name: "forum_uploads_nonnegative_manual_review_version"
    t.check_constraint "scan_attempts >= 0", name: "forum_uploads_nonnegative_scan_attempts"
    t.check_constraint "scan_status::text = ANY (ARRAY['pending'::character varying::text, 'clean'::character varying::text, 'infected'::character varying::text, 'error'::character varying::text])", name: "forum_uploads_valid_scan_status"
    t.check_constraint "status::text = ANY (ARRAY['reserved'::character varying::text, 'stored'::character varying::text, 'linked'::character varying::text, 'cleanup_pending'::character varying::text, 'cleanup_failed'::character varying::text, 'cleaned'::character varying::text])", name: "forum_uploads_valid_status"
  end

  create_table "forum_user_badges", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "forum_badge_id", null: false
    t.datetime "granted_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["forum_badge_id"], name: "index_forum_user_badges_on_forum_badge_id"
    t.index ["user_id", "forum_badge_id"], name: "index_forum_user_badges_on_user_id_and_forum_badge_id", unique: true
    t.index ["user_id"], name: "index_forum_user_badges_on_user_id"
  end

  create_table "forum_user_blocks", force: :cascade do |t|
    t.bigint "blocked_id", null: false
    t.bigint "blocker_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["blocked_id"], name: "index_forum_user_blocks_on_blocked_id"
    t.index ["blocker_id", "blocked_id"], name: "index_forum_user_blocks_on_blocker_id_and_blocked_id", unique: true
    t.index ["blocker_id"], name: "index_forum_user_blocks_on_blocker_id"
  end

  create_table "forum_user_field_definitions", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.text "choices"
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "editable_by_user", default: true, null: false
    t.string "field_type", default: "text", null: false
    t.string "key", null: false
    t.string "label", null: false
    t.boolean "required", default: false, null: false
    t.boolean "show_on_profile", default: true, null: false
    t.boolean "show_on_registration", default: false, null: false
    t.integer "sort_order", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "visibility", default: "public", null: false
    t.index ["key"], name: "index_forum_user_field_definitions_on_key", unique: true
  end

  create_table "forum_user_field_values", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "forum_user_field_definition_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.text "value"
    t.index ["forum_user_field_definition_id"], name: "idx_on_forum_user_field_definition_id_df4b56a372"
    t.index ["user_id", "forum_user_field_definition_id"], name: "index_forum_user_field_values_on_user_and_definition", unique: true
    t.index ["user_id"], name: "index_forum_user_field_values_on_user_id"
  end

  create_table "forum_user_follows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "followed_id", null: false
    t.bigint "follower_id", null: false
    t.datetime "updated_at", null: false
    t.index ["followed_id"], name: "index_forum_user_follows_on_followed_id"
    t.index ["follower_id", "followed_id"], name: "index_forum_user_follows_on_follower_id_and_followed_id", unique: true
    t.index ["follower_id"], name: "index_forum_user_follows_on_follower_id"
  end

  create_table "forum_user_ignores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "ignored_id", null: false
    t.bigint "ignorer_id", null: false
    t.datetime "updated_at", null: false
    t.index ["ignored_id"], name: "index_forum_user_ignores_on_ignored_id"
    t.index ["ignorer_id", "ignored_id"], name: "index_forum_user_ignores_on_ignorer_id_and_ignored_id", unique: true
    t.index ["ignorer_id"], name: "index_forum_user_ignores_on_ignorer_id"
  end

  create_table "forum_user_silences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id", null: false
    t.datetime "expires_at"
    t.text "reason"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["created_by_id"], name: "index_forum_user_silences_on_created_by_id"
    t.index ["user_id", "expires_at"], name: "index_forum_user_silences_on_user_id_and_expires_at"
    t.index ["user_id"], name: "index_forum_user_silences_on_user_id"
  end

  create_table "forum_user_title_ladders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "min_posts", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["min_posts"], name: "index_forum_user_title_ladders_on_min_posts"
  end

  create_table "forum_user_warnings", force: :cascade do |t|
    t.boolean "acknowledged", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.bigint "issuer_id", null: false
    t.integer "points", default: 1, null: false
    t.text "reason", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["expires_at"], name: "index_forum_user_warnings_on_expires_at"
    t.index ["issuer_id"], name: "index_forum_user_warnings_on_issuer_id"
    t.index ["user_id"], name: "index_forum_user_warnings_on_user_id"
  end

  create_table "forum_warning_templates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "expire_days"
    t.string "name", null: false
    t.integer "points", default: 1, null: false
    t.integer "position", default: 0, null: false
    t.text "reason", default: "", null: false
    t.datetime "updated_at", null: false
  end

  create_table "frontend_templates", force: :cascade do |t|
    t.string "checksum", default: "", null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "installed_path"
    t.string "key", null: false
    t.jsonb "manifest", default: {}, null: false
    t.string "name", null: false
    t.jsonb "scopes", default: [], null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.string "version", default: "1.0.0", null: false
    t.index ["key"], name: "index_frontend_templates_on_key", unique: true
    t.index ["status"], name: "index_frontend_templates_on_status"
  end

  create_table "identity_data_exports", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "error_code"
    t.datetime "expires_at"
    t.datetime "failed_at"
    t.string "format", default: "zip", null: false
    t.string "idempotency_key", null: false
    t.integer "lock_version", default: 0, null: false
    t.jsonb "manifest", default: {}, null: false
    t.string "public_id", null: false
    t.datetime "requested_at", null: false
    t.datetime "revoked_at"
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["public_id"], name: "index_identity_data_exports_on_public_id", unique: true
    t.index ["user_id", "idempotency_key"], name: "idx_identity_exports_idempotency", unique: true
    t.index ["user_id", "status", "requested_at"], name: "idx_identity_exports_user_status"
    t.index ["user_id"], name: "index_identity_data_exports_on_user_id"
    t.check_constraint "status::text = ANY (ARRAY['queued'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'revoked'::character varying::text, 'expired'::character varying::text])", name: "chk_identity_data_exports_status"
  end

  create_table "installation_locks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "locked", default: false, null: false
    t.datetime "locked_at"
    t.bigint "locked_by_id"
    t.datetime "updated_at", null: false
    t.index ["locked_by_id"], name: "index_installation_locks_on_locked_by_id"
  end

  create_table "ip_bans", force: :cascade do |t|
    t.bigint "banned_by_id"
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "ip_address", null: false
    t.text "reason"
    t.datetime "updated_at", null: false
    t.index ["banned_by_id"], name: "index_ip_bans_on_banned_by_id"
    t.index ["ip_address"], name: "index_ip_bans_on_ip_address", unique: true
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
    t.index ["store_fulfillment_id"], name: "index_minecraft_connector_tasks_on_store_fulfillment_id", unique: true
  end

  create_table "minecraft_identities", force: :cascade do |t|
    t.string "cape_texture_url"
    t.datetime "created_at", null: false
    t.string "identity_type", default: "java", null: false
    t.datetime "last_seen_ingame_at"
    t.datetime "linked_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "minecraft_server_id"
    t.bigint "player_profile_id"
    t.string "skin_model"
    t.string "skin_texture_url"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "username", null: false
    t.string "uuid", null: false
    t.index ["minecraft_server_id"], name: "index_minecraft_identities_on_minecraft_server_id"
    t.index ["player_profile_id"], name: "index_minecraft_identities_on_player_profile_id"
    t.index ["user_id"], name: "index_minecraft_identities_on_user_id"
    t.index ["uuid", "identity_type"], name: "index_minecraft_identities_on_uuid_and_identity_type", unique: true
  end

  create_table "minecraft_identity_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "linked_at", null: false
    t.integer "lock_version", default: 0, null: false
    t.bigint "player_profile_id", null: false
    t.boolean "primary_account", default: false, null: false
    t.string "unlink_idempotency_key_digest", limit: 64
    t.datetime "unlinked_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["player_profile_id", "user_id"], name: "idx_on_player_profile_id_user_id_a518a2f67b", unique: true, where: "(unlinked_at IS NULL)"
    t.index ["player_profile_id"], name: "index_minecraft_identity_links_on_player_profile_id"
    t.index ["user_id", "unlink_idempotency_key_digest"], name: "idx_mc_identity_links_unlink_idempotency", unique: true, where: "(unlink_idempotency_key_digest IS NOT NULL)"
    t.index ["user_id"], name: "idx_mc_identity_links_one_primary_per_user", unique: true, where: "((unlinked_at IS NULL) AND (primary_account = true))"
    t.index ["user_id"], name: "index_minecraft_identity_links_on_user_id"
    t.check_constraint "lock_version >= 0", name: "mc_identity_links_lock_version"
    t.check_constraint "unlink_idempotency_key_digest IS NULL OR unlink_idempotency_key_digest::text ~ '^[0-9a-f]{64}$'::text", name: "mc_identity_links_unlink_digest_format"
  end

  create_table "minecraft_integration_action_logs", force: :cascade do |t|
    t.jsonb "completed_effects", default: [], null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "event_id", null: false
    t.string "event_key", null: false
    t.bigint "integration_action_id"
    t.jsonb "payload", default: {}, null: false
    t.string "status", default: "completed", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_minecraft_integration_action_logs_on_event_id", unique: true
    t.index ["integration_action_id"], name: "idx_on_integration_action_id_fcd7877343"
  end

  create_table "minecraft_integration_actions", force: :cascade do |t|
    t.jsonb "actions", default: [], null: false
    t.jsonb "conditions", default: {}, null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.string "event_key", null: false
    t.string "name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["event_key"], name: "index_minecraft_integration_actions_on_event_key"
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

  create_table "minecraft_node_metric_snapshots", force: :cascade do |t|
    t.float "cpu_percent"
    t.datetime "created_at", null: false
    t.bigint "disk_total_bytes"
    t.bigint "disk_used_bytes"
    t.integer "max_players"
    t.bigint "mem_total_bytes"
    t.bigint "mem_used_bytes"
    t.jsonb "metadata", default: {}, null: false
    t.bigint "minecraft_node_id", null: false
    t.bigint "minecraft_server_id"
    t.integer "online_players"
    t.datetime "recorded_at", null: false
    t.float "tps"
    t.datetime "updated_at", null: false
    t.index ["minecraft_node_id", "recorded_at"], name: "idx_on_minecraft_node_id_recorded_at_bbb9851ffe"
    t.index ["minecraft_node_id"], name: "index_minecraft_node_metric_snapshots_on_minecraft_node_id"
    t.index ["minecraft_server_id", "recorded_at"], name: "idx_on_minecraft_server_id_recorded_at_d82cc9af1c"
    t.index ["minecraft_server_id"], name: "index_minecraft_node_metric_snapshots_on_minecraft_server_id"
  end

  create_table "minecraft_node_operation_batches", force: :cascade do |t|
    t.datetime "acknowledged_at"
    t.string "acknowledgement_id"
    t.datetime "claimed_at"
    t.datetime "completed_at"
    t.integer "completed_target_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "delivery_attempts", default: 0, null: false
    t.string "delivery_id", null: false
    t.integer "failed_target_count", default: 0, null: false
    t.datetime "lease_expires_at"
    t.integer "lock_version", default: 0, null: false
    t.bigint "minecraft_node_id", null: false
    t.bigint "minecraft_node_operation_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.string "payload_digest", null: false
    t.string "public_id", null: false
    t.jsonb "result", default: {}, null: false
    t.string "result_digest"
    t.datetime "result_recorded_at"
    t.datetime "started_at"
    t.string "status", default: "ready", null: false
    t.integer "target_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["acknowledgement_id"], name: "idx_minecraft_node_batches_ack_id", unique: true, where: "(acknowledgement_id IS NOT NULL)"
    t.index ["delivery_id"], name: "idx_minecraft_node_batches_delivery_id", unique: true
    t.index ["minecraft_node_id", "status", "created_at"], name: "idx_minecraft_node_batches_dispatch"
    t.index ["minecraft_node_id"], name: "idx_minecraft_node_batches_node"
    t.index ["minecraft_node_id"], name: "idx_minecraft_node_batches_one_active", unique: true, where: "((status)::text = ANY (ARRAY[('dispatched'::character varying)::text, ('running'::character varying)::text, ('result_pending_ack'::character varying)::text]))"
    t.index ["minecraft_node_operation_id", "minecraft_node_id"], name: "idx_minecraft_node_batches_operation_node", unique: true
    t.index ["minecraft_node_operation_id"], name: "idx_minecraft_node_batches_operation"
    t.index ["public_id"], name: "idx_minecraft_node_batches_public_id", unique: true
  end

  create_table "minecraft_node_operation_target_results", force: :cascade do |t|
    t.datetime "applied_at"
    t.string "applied_revision"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "error_code"
    t.text "error_message"
    t.string "expected_revision"
    t.bigint "minecraft_node_operation_batch_id", null: false
    t.bigint "minecraft_server_id"
    t.jsonb "result", default: {}, null: false
    t.datetime "started_at"
    t.string "status", null: false
    t.string "target_key", null: false
    t.datetime "updated_at", null: false
    t.index ["minecraft_node_operation_batch_id", "target_key"], name: "idx_minecraft_node_target_results_unique", unique: true
    t.index ["minecraft_node_operation_batch_id"], name: "idx_minecraft_node_target_results_batch"
    t.index ["minecraft_server_id"], name: "idx_minecraft_node_target_results_server"
  end

  create_table "minecraft_node_operations", force: :cascade do |t|
    t.integer "batch_count", default: 0, null: false
    t.datetime "completed_at"
    t.integer "completed_target_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "dispatch_slot"
    t.integer "failed_target_count", default: 0, null: false
    t.string "idempotency_key"
    t.string "operation_type", null: false
    t.string "public_id", null: false
    t.string "request_digest", null: false
    t.jsonb "request_payload", default: {}, null: false
    t.jsonb "result", default: {}, null: false
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.integer "target_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["dispatch_slot"], name: "idx_minecraft_node_operations_single_dispatch", unique: true, where: "(dispatch_slot IS NOT NULL)"
    t.index ["idempotency_key"], name: "index_minecraft_node_operations_on_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["public_id"], name: "index_minecraft_node_operations_on_public_id", unique: true
    t.index ["status", "created_at"], name: "index_minecraft_node_operations_on_status_and_created_at"
    t.check_constraint "dispatch_slot IS NULL OR dispatch_slot = 1", name: "minecraft_node_operations_dispatch_slot_value"
  end

  create_table "minecraft_node_tasks", force: :cascade do |t|
    t.datetime "claimed_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "delivery_id"
    t.bigint "minecraft_node_id", null: false
    t.bigint "minecraft_server_id"
    t.jsonb "payload", default: {}, null: false
    t.string "priority", default: "normal", null: false
    t.jsonb "result", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.string "task_type", null: false
    t.datetime "updated_at", null: false
    t.index ["delivery_id"], name: "index_minecraft_node_tasks_on_delivery_id", unique: true, where: "(delivery_id IS NOT NULL)"
    t.index ["minecraft_node_id", "status", "priority"], name: "idx_on_minecraft_node_id_status_priority_8716bbda9c"
    t.index ["minecraft_node_id", "status"], name: "index_minecraft_node_tasks_on_minecraft_node_id_and_status"
    t.index ["minecraft_node_id"], name: "index_minecraft_node_tasks_on_minecraft_node_id"
    t.index ["minecraft_server_id"], name: "index_minecraft_node_tasks_on_minecraft_server_id"
  end

  create_table "minecraft_nodes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "encrypted_node_secret"
    t.string "hostname"
    t.datetime "last_heartbeat_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.string "node_secret_fingerprint"
    t.string "proxy_listen_url", default: "http://127.0.0.1:9876"
    t.string "public_id", null: false
    t.string "status", default: "offline", null: false
    t.datetime "tasks_wake_at"
    t.datetime "updated_at", null: false
    t.index ["public_id"], name: "index_minecraft_nodes_on_public_id", unique: true
  end

  create_table "minecraft_permission_groups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "group_key", null: false
    t.string "group_label"
    t.bigint "player_profile_id", null: false
    t.string "source", default: "manual", null: false
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.integer "weight", default: 0, null: false
    t.index ["player_profile_id", "group_key"], name: "idx_on_player_profile_id_group_key_1156207531", unique: true
    t.index ["player_profile_id"], name: "index_minecraft_permission_groups_on_player_profile_id"
  end

  create_table "minecraft_player_identities", force: :cascade do |t|
    t.string "cape_texture_sha256", limit: 64
    t.string "cape_texture_url"
    t.datetime "created_at", null: false
    t.string "external_uuid", null: false
    t.string "identity_type", default: "java", null: false
    t.datetime "last_seen_ingame_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "platform", default: "java", null: false
    t.bigint "player_profile_id", null: false
    t.bigint "primary_server_id"
    t.integer "skin_cache_version", default: 0, null: false
    t.datetime "skin_cached_at"
    t.string "skin_model"
    t.datetime "skin_refresh_attempted_at"
    t.string "skin_refresh_error_code"
    t.datetime "skin_refresh_failed_at"
    t.string "skin_texture_sha256", limit: 64
    t.string "skin_texture_url"
    t.datetime "superseded_at"
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.datetime "valid_from", null: false
    t.index ["platform", "external_uuid"], name: "idx_on_platform_external_uuid_9bc1c89e08", unique: true, where: "(superseded_at IS NULL)"
    t.index ["player_profile_id"], name: "index_minecraft_player_identities_on_player_profile_id"
    t.index ["primary_server_id"], name: "index_minecraft_player_identities_on_primary_server_id"
    t.index ["superseded_at", "skin_cached_at"], name: "idx_mc_player_identities_skin_cache_due"
    t.index ["username"], name: "index_minecraft_player_identities_on_username"
  end

  create_table "minecraft_player_profiles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "public_id", null: false
    t.datetime "updated_at", null: false
    t.index ["public_id"], name: "index_minecraft_player_profiles_on_public_id", unique: true
  end

  create_table "minecraft_player_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "ended_at"
    t.datetime "joined_at", null: false
    t.bigint "minecraft_server_id", null: false
    t.bigint "player_profile_id", null: false
    t.string "source", default: "connector", null: false
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.index ["minecraft_server_id", "ended_at"], name: "idx_on_minecraft_server_id_ended_at_3aaf29f636"
    t.index ["minecraft_server_id"], name: "index_minecraft_player_sessions_on_minecraft_server_id"
    t.index ["player_profile_id", "ended_at"], name: "idx_on_player_profile_id_ended_at_a039423057"
    t.index ["player_profile_id"], name: "index_minecraft_player_sessions_on_player_profile_id"
  end

  create_table "minecraft_primary_account_change_events", force: :cascade do |t|
    t.bigint "actor_id", null: false
    t.string "change_source", null: false
    t.datetime "changed_at", null: false
    t.boolean "counts_for_cooldown", default: true, null: false
    t.datetime "created_at", null: false
    t.bigint "from_identity_link_id"
    t.string "idempotency_key_digest", limit: 64, null: false
    t.bigint "primary_account_change_request_id"
    t.text "reason"
    t.bigint "to_identity_link_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["actor_id"], name: "index_minecraft_primary_account_change_events_on_actor_id"
    t.index ["from_identity_link_id"], name: "idx_on_from_identity_link_id_8d7336ca35"
    t.index ["primary_account_change_request_id"], name: "idx_mc_primary_events_request", unique: true, where: "(primary_account_change_request_id IS NOT NULL)"
    t.index ["primary_account_change_request_id"], name: "idx_on_primary_account_change_request_id_dbc28f07ae"
    t.index ["to_identity_link_id"], name: "idx_on_to_identity_link_id_a935602661"
    t.index ["user_id", "changed_at"], name: "idx_mc_primary_events_user_changed"
    t.index ["user_id", "idempotency_key_digest"], name: "idx_mc_primary_events_idempotency", unique: true
    t.index ["user_id"], name: "index_minecraft_primary_account_change_events_on_user_id"
    t.check_constraint "change_source::text <> 'administrator_override'::text OR btrim(COALESCE(reason, ''::text)) <> ''::text", name: "mc_primary_events_admin_reason"
    t.check_constraint "change_source::text = ANY (ARRAY['player_immediate'::character varying::text, 'staff_approval'::character varying::text, 'administrator_override'::character varying::text, 'automatic_successor'::character varying::text])", name: "mc_primary_events_source"
    t.check_constraint "from_identity_link_id IS NULL OR from_identity_link_id <> to_identity_link_id", name: "mc_primary_events_distinct_links"
    t.check_constraint "idempotency_key_digest::text ~ '^[0-9a-f]{64}$'::text", name: "mc_primary_events_digest"
  end

  create_table "minecraft_primary_account_change_requests", force: :cascade do |t|
    t.datetime "applied_at"
    t.datetime "created_at", null: false
    t.bigint "decided_by_id"
    t.text "decision_reason"
    t.datetime "expires_at", null: false
    t.string "idempotency_key_digest", limit: 64, null: false
    t.integer "lock_version", default: 0, null: false
    t.string "policy_snapshot", default: "staff_approval", null: false
    t.text "request_reason", null: false
    t.datetime "requested_at", null: false
    t.bigint "requested_by_id", null: false
    t.datetime "resolved_at"
    t.bigint "source_identity_link_id"
    t.string "status", default: "pending", null: false
    t.bigint "target_identity_link_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["decided_by_id"], name: "idx_on_decided_by_id_f79a8d6a81"
    t.index ["requested_by_id"], name: "idx_on_requested_by_id_ec1462ee85"
    t.index ["source_identity_link_id"], name: "idx_on_source_identity_link_id_fa1efd1976"
    t.index ["target_identity_link_id", "status"], name: "idx_mc_primary_requests_target_status"
    t.index ["target_identity_link_id"], name: "idx_on_target_identity_link_id_e236c563d1"
    t.index ["user_id", "idempotency_key_digest"], name: "idx_mc_primary_requests_idempotency", unique: true
    t.index ["user_id", "status", "requested_at"], name: "idx_mc_primary_requests_user_status"
    t.index ["user_id"], name: "idx_mc_primary_requests_one_pending", unique: true, where: "((status)::text = 'pending'::text)"
    t.index ["user_id"], name: "index_minecraft_primary_account_change_requests_on_user_id"
    t.check_constraint "btrim(request_reason) <> ''::text", name: "mc_primary_requests_reason"
    t.check_constraint "expires_at > requested_at", name: "mc_primary_requests_expiry"
    t.check_constraint "idempotency_key_digest::text ~ '^[0-9a-f]{64}$'::text", name: "mc_primary_requests_digest"
    t.check_constraint "policy_snapshot::text = 'staff_approval'::text", name: "mc_primary_requests_policy"
    t.check_constraint "source_identity_link_id IS NULL OR source_identity_link_id <> target_identity_link_id", name: "mc_primary_requests_distinct_links"
    t.check_constraint "status::text = 'pending'::text AND resolved_at IS NULL AND applied_at IS NULL AND decided_by_id IS NULL OR status::text = 'approved'::text AND resolved_at IS NOT NULL AND applied_at IS NOT NULL AND decided_by_id IS NOT NULL OR status::text = 'rejected'::text AND resolved_at IS NOT NULL AND applied_at IS NULL AND decided_by_id IS NOT NULL AND btrim(COALESCE(decision_reason, ''::text)) <> ''::text OR status::text = 'expired'::text AND resolved_at IS NOT NULL AND applied_at IS NULL AND decided_by_id IS NULL OR status::text = 'cancelled'::text AND resolved_at IS NOT NULL AND applied_at IS NULL", name: "mc_primary_requests_resolution_shape"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'approved'::character varying::text, 'rejected'::character varying::text, 'expired'::character varying::text, 'cancelled'::character varying::text])", name: "mc_primary_requests_status"
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

  create_table "minecraft_profile_field_definitions", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "field_type", default: "text", null: false
    t.string "group_name"
    t.string "icon"
    t.string "key", null: false
    t.string "label", null: false
    t.integer "sort_order", default: 0, null: false
    t.string "source", default: "plugin", null: false
    t.datetime "updated_at", null: false
    t.string "visibility", default: "public", null: false
    t.index ["key"], name: "index_minecraft_profile_field_definitions_on_key", unique: true
  end

  create_table "minecraft_profile_field_values", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "field_key", null: false
    t.bigint "player_profile_id", null: false
    t.datetime "updated_at", null: false
    t.string "updated_by", default: "plugin", null: false
    t.text "value"
    t.index ["player_profile_id", "field_key"], name: "idx_on_player_profile_id_field_key_7dd58d55e1", unique: true
    t.index ["player_profile_id"], name: "index_minecraft_profile_field_values_on_player_profile_id"
  end

  create_table "minecraft_server_snapshots", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "max_players", default: 0, null: false
    t.bigint "memory_max_bytes"
    t.bigint "memory_used_bytes"
    t.jsonb "metadata", default: {}, null: false
    t.bigint "minecraft_server_id", null: false
    t.string "motd"
    t.integer "online_players", default: 0, null: false
    t.jsonb "plugins", default: [], null: false
    t.float "tps"
    t.datetime "updated_at", null: false
    t.string "version"
    t.jsonb "worlds", default: [], null: false
    t.index ["minecraft_server_id", "created_at"], name: "idx_on_minecraft_server_id_created_at_9b27186894"
    t.index ["minecraft_server_id"], name: "index_minecraft_server_snapshots_on_minecraft_server_id"
  end

  create_table "minecraft_servers", force: :cascade do |t|
    t.string "address"
    t.string "connection_mode", default: "direct", null: false
    t.string "connector_secret_fingerprint"
    t.datetime "created_at", null: false
    t.text "encrypted_connector_secret"
    t.datetime "last_heartbeat_at"
    t.integer "max_players", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "minecraft_node_id"
    t.string "name", null: false
    t.integer "online_players", default: 0, null: false
    t.integer "port", default: 25565, null: false
    t.jsonb "process_config", default: {}, null: false
    t.string "process_driver"
    t.string "process_state", default: "stopped", null: false
    t.string "proxy_listen_url"
    t.string "public_id", null: false
    t.string "status", default: "offline", null: false
    t.datetime "updated_at", null: false
    t.string "version"
    t.string "working_directory"
    t.index ["minecraft_node_id"], name: "index_minecraft_servers_on_minecraft_node_id"
    t.index ["public_id"], name: "index_minecraft_servers_on_public_id", unique: true
  end

  create_table "minecraft_skin_refresh_requests", force: :cascade do |t|
    t.boolean "cache_changed", default: false, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "error_code"
    t.string "idempotency_key_digest", limit: 64, null: false
    t.bigint "player_identity_id", null: false
    t.bigint "requested_by_id"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.string "trigger", default: "scheduled", null: false
    t.datetime "updated_at", null: false
    t.index ["player_identity_id", "idempotency_key_digest"], name: "idx_mc_skin_refresh_requests_idempotency", unique: true
    t.index ["player_identity_id"], name: "index_minecraft_skin_refresh_requests_on_player_identity_id"
    t.index ["requested_by_id"], name: "index_minecraft_skin_refresh_requests_on_requested_by_id"
    t.index ["status", "started_at"], name: "idx_mc_skin_refresh_requests_recovery"
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
    t.boolean "auto_dismiss", default: false, null: false
    t.text "body"
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "notification_type", null: false
    t.datetime "read_at"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "created_at", "notification_type"], name: "idx_notifications_unread_user_created", order: { created_at: :desc }, where: "(read_at IS NULL)"
    t.index ["user_id", "created_at"], name: "idx_notifications_user_created", order: { created_at: :desc }
    t.index ["user_id", "notification_type", "created_at"], name: "idx_notifications_user_type_created", order: { created_at: :desc }
    t.index ["user_id", "read_at"], name: "index_notifications_on_user_id_and_read_at"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "operations_durable_enqueue_attempts", force: :cascade do |t|
    t.integer "attempt_number", null: false
    t.datetime "created_at", null: false
    t.integer "generation", null: false
    t.bigint "intent_id", null: false
    t.string "job_id", limit: 160, null: false
    t.datetime "lease_expires_at", null: false
    t.string "lease_token", limit: 36, null: false
    t.datetime "started_at", null: false
    t.string "trigger", limit: 32, null: false
    t.datetime "updated_at", null: false
    t.index ["intent_id", "attempt_number"], name: "idx_operations_durable_attempts_sequence", unique: true
    t.index ["intent_id", "generation", "attempt_number"], name: "idx_operations_durable_attempts_generation"
    t.index ["intent_id"], name: "index_operations_durable_enqueue_attempts_on_intent_id"
    t.index ["lease_expires_at", "intent_id"], name: "idx_operations_durable_attempts_lease"
    t.index ["lease_token"], name: "index_operations_durable_enqueue_attempts_on_lease_token", unique: true
    t.check_constraint "attempt_number > 0", name: "operations_durable_attempts_number"
    t.check_constraint "generation > 0", name: "operations_durable_attempts_generation"
    t.check_constraint "lease_expires_at > started_at", name: "operations_durable_attempts_lease_window"
    t.check_constraint "lease_token::text ~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'::text", name: "operations_durable_attempts_lease_token"
    t.check_constraint "trigger::text = ANY (ARRAY['after_commit'::character varying::text, 'maintenance'::character varying::text, 'manual'::character varying::text])", name: "operations_durable_attempts_trigger"
  end

  create_table "operations_durable_enqueue_events", force: :cascade do |t|
    t.bigint "attempt_id"
    t.datetime "available_at"
    t.datetime "created_at", null: false
    t.string "error_code", limit: 120
    t.string "event_type", limit: 64, null: false
    t.integer "generation", null: false
    t.bigint "intent_id", null: false
    t.datetime "lease_expires_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.integer "sequence", null: false
    t.datetime "updated_at", null: false
    t.index ["attempt_id", "event_type"], name: "idx_operations_durable_events_attempt"
    t.index ["attempt_id"], name: "idx_operations_durable_events_attempt_outcome", unique: true, where: "((event_type)::text = ANY (ARRAY[('attempt_succeeded'::character varying)::text, ('attempt_skipped'::character varying)::text, ('attempt_failed'::character varying)::text]))"
    t.index ["attempt_id"], name: "idx_operations_durable_events_attempt_started", unique: true, where: "((event_type)::text = 'attempt_started'::text)"
    t.index ["attempt_id"], name: "index_operations_durable_enqueue_events_on_attempt_id"
    t.index ["attempt_id"], name: "index_operations_durable_events_unique_lease_expired", unique: true, where: "((event_type)::text = 'lease_expired'::text)"
    t.index ["event_type", "available_at", "intent_id"], name: "idx_operations_durable_events_recovery"
    t.index ["intent_id", "generation", "sequence"], name: "idx_operations_durable_events_generation"
    t.index ["intent_id", "sequence"], name: "idx_operations_durable_events_sequence", unique: true
    t.index ["intent_id"], name: "index_operations_durable_enqueue_events_on_intent_id"
    t.check_constraint "(event_type::text = ANY (ARRAY['attempt_started'::character varying::text, 'lease_renewed'::character varying::text, 'attempt_succeeded'::character varying::text, 'attempt_skipped'::character varying::text, 'attempt_failed'::character varying::text, 'lease_expired'::character varying::text])) AND attempt_id IS NOT NULL OR (event_type::text <> ALL (ARRAY['attempt_started'::character varying::text, 'lease_renewed'::character varying::text, 'attempt_succeeded'::character varying::text, 'attempt_skipped'::character varying::text, 'attempt_failed'::character varying::text, 'lease_expired'::character varying::text])) AND attempt_id IS NULL", name: "operations_durable_events_attempt_shape"
    t.check_constraint "(event_type::text = ANY (ARRAY['enqueue_failed'::character varying::text, 'attempt_failed'::character varying::text, 'retry_scheduled'::character varying::text, 'dead_lettered'::character varying::text, 'attempt_skipped'::character varying::text])) AND error_code IS NOT NULL OR (event_type::text <> ALL (ARRAY['enqueue_failed'::character varying::text, 'attempt_failed'::character varying::text, 'retry_scheduled'::character varying::text, 'dead_lettered'::character varying::text, 'attempt_skipped'::character varying::text])) AND error_code IS NULL", name: "operations_durable_events_error_shape"
    t.check_constraint "error_code IS NULL OR error_code::text ~ '^[a-z][a-z0-9_]*$'::text", name: "operations_durable_events_error_code"
    t.check_constraint "event_type::text <> 'reopened'::text OR metadata ? 'actor_id'::text AND metadata ? 'reason'::text AND COALESCE((metadata ->> 'actor_id'::text) ~ '^[1-9][0-9]*$'::text, false) AND COALESCE(length(btrim(metadata ->> 'reason'::text)) >= 1 AND length(btrim(metadata ->> 'reason'::text)) <= 500, false)", name: "operations_durable_events_reopened_shape"
    t.check_constraint "event_type::text = 'lease_renewed'::text AND lease_expires_at IS NOT NULL AND lease_expires_at > occurred_at OR event_type::text <> 'lease_renewed'::text AND lease_expires_at IS NULL", name: "operations_durable_events_lease_shape"
    t.check_constraint "event_type::text = 'retry_scheduled'::text AND available_at IS NOT NULL OR event_type::text <> 'retry_scheduled'::text AND available_at IS NULL", name: "operations_durable_events_available_shape"
    t.check_constraint "event_type::text = ANY (ARRAY['recorded'::character varying::text, 'enqueue_requested'::character varying::text, 'enqueue_succeeded'::character varying::text, 'enqueue_failed'::character varying::text, 'attempt_started'::character varying::text, 'lease_renewed'::character varying::text, 'attempt_succeeded'::character varying::text, 'attempt_skipped'::character varying::text, 'attempt_failed'::character varying::text, 'lease_expired'::character varying::text, 'retry_scheduled'::character varying::text, 'dead_lettered'::character varying::text, 'reopened'::character varying::text])", name: "operations_durable_events_type"
    t.check_constraint "generation > 0", name: "operations_durable_events_generation"
    t.check_constraint "jsonb_typeof(metadata) = 'object'::text AND octet_length(metadata::text) <= 4096", name: "operations_durable_events_metadata"
    t.check_constraint "sequence > 0", name: "operations_durable_events_sequence"
  end

  create_table "operations_durable_enqueue_intents", force: :cascade do |t|
    t.jsonb "arguments", default: {}, null: false
    t.string "arguments_sha256", limit: 64, null: false
    t.datetime "created_at", null: false
    t.string "dedupe_key", limit: 191, null: false
    t.string "handler_key", limit: 120, null: false
    t.string "public_id", limit: 36, null: false
    t.string "queue_name", limit: 64, null: false
    t.datetime "requested_at", null: false
    t.bigint "source_id", null: false
    t.string "source_kind", limit: 120, null: false
    t.datetime "updated_at", null: false
    t.index ["handler_key", "dedupe_key"], name: "idx_operations_durable_intents_dedupe", unique: true
    t.index ["handler_key", "requested_at", "id"], name: "idx_operations_durable_intents_handler"
    t.index ["public_id"], name: "index_operations_durable_enqueue_intents_on_public_id", unique: true
    t.index ["source_kind", "source_id"], name: "idx_operations_durable_intents_source"
    t.check_constraint "arguments_sha256::text ~ '^[0-9a-f]{64}$'::text", name: "operations_durable_intents_digest"
    t.check_constraint "dedupe_key::text ~ '^[a-zA-Z0-9][a-zA-Z0-9._:/-]*$'::text", name: "operations_durable_intents_dedupe_key"
    t.check_constraint "handler_key::text ~ '^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)+$'::text", name: "operations_durable_intents_handler_key"
    t.check_constraint "jsonb_typeof(arguments) = 'object'::text AND octet_length(arguments::text) <= 8192", name: "operations_durable_intents_arguments"
    t.check_constraint "public_id::text ~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'::text", name: "operations_durable_intents_public_id"
    t.check_constraint "queue_name::text ~ '^[a-z][a-z0-9_]*$'::text", name: "operations_durable_intents_queue"
    t.check_constraint "source_id > 0", name: "operations_durable_intents_source_id"
    t.check_constraint "source_kind::text ~ '^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)*$'::text", name: "operations_durable_intents_source_kind"
  end

  create_table "operations_manual_task_runs", force: :cascade do |t|
    t.jsonb "arguments", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "error_code"
    t.text "error_message"
    t.datetime "finished_at"
    t.string "idempotency_key", null: false
    t.string "job_id"
    t.integer "lock_version", default: 0, null: false
    t.datetime "requested_at", null: false
    t.bigint "requested_by_id"
    t.jsonb "result", default: {}, null: false
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.string "task_key", null: false
    t.datetime "updated_at", null: false
    t.index ["requested_by_id"], name: "index_operations_manual_task_runs_on_requested_by_id"
    t.index ["status", "requested_at"], name: "idx_operations_manual_tasks_status"
    t.index ["task_key", "idempotency_key"], name: "idx_operations_manual_tasks_idempotency", unique: true
    t.check_constraint "(status::text = ANY (ARRAY['queued'::character varying::text, 'running'::character varying::text])) AND finished_at IS NULL OR (status::text = ANY (ARRAY['succeeded'::character varying::text, 'failed'::character varying::text])) AND finished_at IS NOT NULL", name: "operations_manual_task_runs_finished_shape"
    t.check_constraint "status::text = ANY (ARRAY['queued'::character varying::text, 'running'::character varying::text, 'succeeded'::character varying::text, 'failed'::character varying::text])", name: "operations_manual_task_runs_status"
  end

  create_table "operations_metric_buckets", force: :cascade do |t|
    t.datetime "bucket_at", null: false
    t.datetime "created_at", null: false
    t.jsonb "dimensions", default: {}, null: false
    t.string "dimensions_key", limit: 64, null: false
    t.string "metric_name", limit: 96, null: false
    t.bigint "sample_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.decimal "value_max", precision: 20, scale: 6, default: "0.0", null: false
    t.decimal "value_min", precision: 20, scale: 6, default: "0.0", null: false
    t.decimal "value_sum", precision: 30, scale: 6, default: "0.0", null: false
    t.index ["bucket_at", "metric_name", "dimensions_key"], name: "idx_operations_metric_buckets_identity", unique: true
    t.index ["metric_name", "bucket_at"], name: "idx_operations_metric_buckets_trends"
    t.check_constraint "jsonb_typeof(dimensions) = 'object'::text", name: "operations_metric_buckets_dimensions_object"
    t.check_constraint "sample_count > 0", name: "operations_metric_buckets_positive_samples"
    t.check_constraint "value_min <= value_max", name: "operations_metric_buckets_value_range"
  end

  create_table "operations_worker_heartbeats", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_seen_at", null: false
    t.string "process_kind", default: "sidekiq", null: false
    t.string "process_ref", null: false
    t.datetime "started_at", null: false
    t.datetime "updated_at", null: false
    t.index ["process_kind", "last_seen_at"], name: "idx_operations_worker_heartbeats_freshness"
    t.index ["process_ref"], name: "index_operations_worker_heartbeats_on_process_ref", unique: true
    t.check_constraint "process_kind::text = 'sidekiq'::text", name: "operations_worker_heartbeats_kind"
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

  create_table "payment_late_payment_cases", force: :cascade do |t|
    t.datetime "acknowledged_at"
    t.bigint "acknowledged_by_id"
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.string "currency", null: false
    t.string "disposition"
    t.integer "lock_version", default: 0, null: false
    t.bigint "payment_record_id", null: false
    t.bigint "payment_webhook_event_id", null: false
    t.string "provider", null: false
    t.string "reason", null: false
    t.text "review_note"
    t.string "status", default: "open", null: false
    t.bigint "store_order_id", null: false
    t.datetime "updated_at", null: false
    t.index ["acknowledged_by_id"], name: "index_payment_late_payment_cases_on_acknowledged_by_id"
    t.index ["payment_record_id"], name: "index_payment_late_payment_cases_on_payment_record_id", unique: true
    t.index ["payment_webhook_event_id"], name: "index_payment_late_payment_cases_on_payment_webhook_event_id", unique: true
    t.index ["provider", "status"], name: "idx_late_payment_cases_provider_status"
    t.index ["reason", "status"], name: "idx_late_payment_cases_reason_status"
    t.index ["status", "created_at"], name: "idx_late_payment_cases_status_created"
    t.index ["store_order_id"], name: "index_payment_late_payment_cases_on_store_order_id"
  end

  create_table "payment_provider_configs", force: :cascade do |t|
    t.string "account_fingerprint", limit: 64
    t.datetime "created_at", null: false
    t.boolean "enabled", default: false, null: false
    t.text "encrypted_credentials"
    t.string "last_connection_test_credential_revision", limit: 64
    t.string "last_connection_test_error_code"
    t.string "last_connection_test_mode"
    t.string "last_connection_test_status"
    t.datetime "last_connection_tested_at"
    t.bigint "last_connection_tested_by_id"
    t.string "mode"
    t.string "provider", null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["last_connection_tested_by_id"], name: "index_payment_provider_configs_on_last_connection_tested_by_id"
    t.index ["provider"], name: "index_payment_provider_configs_on_provider", unique: true
    t.check_constraint "account_fingerprint IS NULL OR account_fingerprint::text ~ '^[0-9a-f]{64}$'::text", name: "payment_provider_configs_account_fingerprint"
    t.check_constraint "last_connection_test_credential_revision IS NULL OR last_connection_test_credential_revision::text ~ '^[0-9a-f]{64}$'::text", name: "payment_provider_configs_test_credential_revision"
    t.check_constraint "last_connection_test_mode IS NULL OR (last_connection_test_mode::text = ANY (ARRAY['test'::character varying::text, 'live'::character varying::text]))", name: "payment_provider_configs_connection_test_mode"
    t.check_constraint "last_connection_test_status IS NULL OR (last_connection_test_status::text = ANY (ARRAY['success'::character varying::text, 'failed'::character varying::text]))", name: "payment_provider_configs_connection_test_status"
    t.check_constraint "last_connection_test_status::text IS DISTINCT FROM 'success'::text OR account_fingerprint IS NOT NULL AND last_connection_test_credential_revision IS NOT NULL", name: "payment_provider_configs_success_identity"
    t.check_constraint "mode IS NULL OR (mode::text = ANY (ARRAY['test'::character varying::text, 'live'::character varying::text]))", name: "payment_provider_configs_mode"
  end

  create_table "payment_reconciliation_discrepancies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "fingerprint", null: false
    t.datetime "first_seen_at", null: false
    t.string "kind", null: false
    t.datetime "last_seen_at", null: false
    t.integer "local_amount_cents"
    t.string "local_currency"
    t.string "local_status"
    t.integer "lock_version", default: 0, null: false
    t.string "mode", null: false
    t.bigint "payment_record_id"
    t.string "provider", null: false
    t.integer "provider_amount_cents"
    t.string "provider_currency"
    t.string "provider_status"
    t.string "public_id", null: false
    t.string "reference_digest", null: false
    t.string "reference_masked"
    t.bigint "refund_id"
    t.datetime "resolved_at"
    t.text "review_note"
    t.datetime "reviewed_at"
    t.bigint "reviewed_by_id"
    t.bigint "run_id", null: false
    t.string "status", default: "open", null: false
    t.bigint "store_order_id"
    t.string "subject_type", null: false
    t.datetime "updated_at", null: false
    t.index ["fingerprint"], name: "idx_payment_recon_discrepancies_fingerprint", unique: true
    t.index ["payment_record_id"], name: "idx_on_payment_record_id_b7f90c939d"
    t.index ["provider", "subject_type", "kind"], name: "idx_payment_recon_discrepancies_filters"
    t.index ["public_id"], name: "idx_payment_recon_discrepancies_public_id", unique: true
    t.index ["refund_id"], name: "index_payment_reconciliation_discrepancies_on_refund_id"
    t.index ["reviewed_by_id"], name: "index_payment_reconciliation_discrepancies_on_reviewed_by_id"
    t.index ["run_id", "status"], name: "idx_payment_recon_discrepancies_run"
    t.index ["status", "created_at"], name: "idx_payment_recon_discrepancies_status"
    t.index ["store_order_id"], name: "index_payment_reconciliation_discrepancies_on_store_order_id"
    t.check_constraint "(local_amount_cents IS NULL OR local_amount_cents >= 0) AND (provider_amount_cents IS NULL OR provider_amount_cents >= 0)", name: "payment_recon_discrepancies_amounts"
    t.check_constraint "mode::text = ANY (ARRAY['test'::character varying::text, 'live'::character varying::text])", name: "payment_recon_discrepancies_mode"
    t.check_constraint "status::text = ANY (ARRAY['open'::character varying::text, 'acknowledged'::character varying::text, 'ignored'::character varying::text, 'resolved'::character varying::text])", name: "payment_recon_discrepancies_status"
    t.check_constraint "subject_type::text = ANY (ARRAY['payment'::character varying::text, 'refund'::character varying::text])", name: "payment_recon_discrepancies_subject"
  end

  create_table "payment_reconciliation_observations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "reference_digest", null: false
    t.bigint "run_id", null: false
    t.string "subject_type", null: false
    t.datetime "updated_at", null: false
    t.index ["run_id", "subject_type", "reference_digest"], name: "idx_payment_recon_observations_unique", unique: true
    t.index ["subject_type", "reference_digest", "run_id"], name: "idx_payment_recon_observations_lookup"
    t.check_constraint "subject_type::text = ANY (ARRAY['payment'::character varying::text, 'refund'::character varying::text])", name: "payment_recon_observations_subject"
  end

  create_table "payment_reconciliation_runs", force: :cascade do |t|
    t.integer "attempt_count", default: 0, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "discrepancies_count", default: 0, null: false
    t.datetime "failed_at"
    t.string "failure_code"
    t.datetime "last_heartbeat_at"
    t.integer "lock_version", default: 0, null: false
    t.string "mode", null: false
    t.string "payment_cursor"
    t.integer "payments_checked", default: 0, null: false
    t.string "phase", default: "payments", null: false
    t.string "processing_token"
    t.string "provider", null: false
    t.integer "refresh_count", default: 0, null: false
    t.datetime "refresh_started_at"
    t.string "refund_cursor"
    t.integer "refunds_checked", default: 0, null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.datetime "window_end", null: false
    t.datetime "window_start", null: false
    t.index ["provider", "mode", "window_start", "window_end"], name: "idx_payment_recon_runs_window", unique: true
    t.index ["status", "last_heartbeat_at"], name: "idx_payment_recon_runs_recovery"
    t.check_constraint "attempt_count >= 0 AND payments_checked >= 0 AND refunds_checked >= 0 AND discrepancies_count >= 0", name: "payment_recon_runs_counters"
    t.check_constraint "mode::text = ANY (ARRAY['test'::character varying::text, 'live'::character varying::text])", name: "payment_recon_runs_mode"
    t.check_constraint "phase::text = ANY (ARRAY['payments'::character varying::text, 'refunds'::character varying::text, 'local_checks'::character varying::text, 'completed'::character varying::text])", name: "payment_recon_runs_phase"
    t.check_constraint "refresh_count >= 0", name: "payment_recon_runs_refresh_count"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'skipped'::character varying::text])", name: "payment_recon_runs_status"
    t.check_constraint "window_end > window_start", name: "payment_recon_runs_window"
  end

  create_table "payment_records", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "CNY", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "provider", null: false
    t.string "provider_mode"
    t.string "provider_payment_id"
    t.string "status", default: "pending", null: false
    t.bigint "store_order_id", null: false
    t.datetime "updated_at", null: false
    t.index "provider, ((metadata ->> 'stripe_payment_intent_id'::text))", name: "idx_payment_records_on_provider_stripe_pi", where: "((metadata ->> 'stripe_payment_intent_id'::text) IS NOT NULL)"
    t.index "provider, provider_mode, ((metadata ->> 'stripe_payment_intent_id'::text))", name: "idx_payment_records_on_mode_stripe_pi", where: "((metadata ->> 'stripe_payment_intent_id'::text) IS NOT NULL)"
    t.index ["provider", "provider_mode", "status", "created_at", "id"], name: "idx_payment_records_reconciliation_mode"
    t.index ["provider", "provider_payment_id"], name: "index_payment_records_on_provider_and_provider_payment_id", unique: true
    t.index ["provider", "status", "created_at", "id"], name: "idx_payment_records_reconciliation_local"
    t.index ["store_order_id"], name: "index_payment_records_on_store_order_id"
    t.check_constraint "provider_mode IS NULL OR (provider_mode::text = ANY (ARRAY['test'::character varying::text, 'live'::character varying::text]))", name: "payment_records_provider_mode"
  end

  create_table "payment_webhook_events", force: :cascade do |t|
    t.integer "attempt_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "dead_lettered_at"
    t.text "error_message"
    t.string "event_id", null: false
    t.string "event_type", null: false
    t.datetime "last_attempted_at"
    t.string "last_error_code"
    t.datetime "last_replayed_at"
    t.bigint "last_replayed_by_id"
    t.integer "manual_replay_count", default: 0, null: false
    t.datetime "next_retry_at"
    t.jsonb "payload", default: {}, null: false
    t.string "payload_digest"
    t.datetime "processed_at"
    t.datetime "processing_started_at"
    t.string "processing_token"
    t.string "provider", null: false
    t.integer "retry_count", default: 0, null: false
    t.string "status", default: "received", null: false
    t.datetime "updated_at", null: false
    t.datetime "verified_at"
    t.index ["dead_lettered_at"], name: "index_payment_webhook_events_on_dead_lettered_at"
    t.index ["last_replayed_by_id"], name: "index_payment_webhook_events_on_last_replayed_by_id"
    t.index ["provider", "event_id"], name: "index_payment_webhook_events_on_provider_and_event_id", unique: true
    t.index ["status", "next_retry_at"], name: "idx_payment_webhooks_status_retry"
    t.index ["status", "processing_started_at"], name: "idx_payment_webhooks_status_processing"
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

  create_table "plugin_contributions", force: :cascade do |t|
    t.string "contribution_id", null: false
    t.string "contribution_type", null: false
    t.datetime "created_at", null: false
    t.jsonb "descriptor", default: {}, null: false
    t.string "descriptor_sha256", null: false
    t.bigint "plugin_release_id", null: false
    t.string "schema_sha256"
    t.datetime "updated_at", null: false
    t.index ["contribution_type", "contribution_id"], name: "idx_on_contribution_type_contribution_id_d592d8a26c"
    t.index ["plugin_release_id", "contribution_id"], name: "idx_plugin_contributions_release_id", unique: true
    t.index ["plugin_release_id"], name: "index_plugin_contributions_on_plugin_release_id"
  end

  create_table "plugin_files", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.datetime "created_at", null: false
    t.boolean "expected", default: true, null: false
    t.string "health", null: false
    t.bigint "observed_byte_size"
    t.string "observed_sha256"
    t.string "path", null: false
    t.bigint "plugin_release_id", null: false
    t.string "sha256", null: false
    t.datetime "updated_at", null: false
    t.index ["health", "updated_at"], name: "index_plugin_files_on_health_and_updated_at"
    t.index ["plugin_release_id", "path"], name: "idx_plugin_files_release_path", unique: true
    t.index ["plugin_release_id"], name: "index_plugin_files_on_plugin_release_id"
    t.check_constraint "byte_size >= 0 AND (observed_byte_size IS NULL OR observed_byte_size >= 0)", name: "plugin_files_nonnegative_sizes"
    t.check_constraint "health::text = ANY (ARRAY['healthy'::character varying::text, 'missing'::character varying::text, 'modified'::character varying::text, 'unknown'::character varying::text, 'unavailable'::character varying::text, 'untracked'::character varying::text])", name: "plugin_files_health"
  end

  create_table "plugin_generations", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "activated_at"
    t.datetime "created_at", null: false
    t.datetime "deadline_at", null: false
    t.jsonb "desired_plugins", default: {}, null: false
    t.string "error_code"
    t.text "error_message"
    t.jsonb "expected_process_uids", default: [], null: false
    t.bigint "initiated_by_id"
    t.integer "lock_version", default: 0, null: false
    t.decimal "minimum_ack_ratio", precision: 5, scale: 4, default: "1.0", null: false
    t.bigint "number", null: false
    t.string "operation_id"
    t.bigint "parent_generation_id"
    t.jsonb "previous_plugins", default: {}, null: false
    t.datetime "rollback_started_at"
    t.datetime "rolled_back_at"
    t.string "state", default: "pending", null: false
    t.string "target_plugin_id"
    t.datetime "updated_at", null: false
    t.index ["initiated_by_id"], name: "index_plugin_generations_on_initiated_by_id"
    t.index ["number"], name: "index_plugin_generations_on_number", unique: true
    t.index ["operation_id"], name: "index_plugin_generations_on_operation_id"
    t.index ["parent_generation_id"], name: "index_plugin_generations_on_parent_generation_id"
    t.index ["state", "number"], name: "index_plugin_generations_on_state_and_number"
  end

  create_table "plugin_installations", force: :cascade do |t|
    t.bigint "active_generation_number"
    t.datetime "created_at", null: false
    t.string "current_state", default: "uploaded", null: false
    t.string "current_version"
    t.string "desired_state", default: "disabled", null: false
    t.string "edition", default: "ce", null: false
    t.string "error_code"
    t.text "error_message"
    t.string "last_operation_id"
    t.integer "lock_version", default: 0, null: false
    t.string "plugin_id", null: false
    t.datetime "updated_at", null: false
    t.index ["current_state", "updated_at"], name: "index_plugin_installations_on_current_state_and_updated_at"
    t.index ["last_operation_id"], name: "index_plugin_installations_on_last_operation_id"
    t.index ["plugin_id"], name: "index_plugin_installations_on_plugin_id", unique: true
  end

  create_table "plugin_job_runs", force: :cascade do |t|
    t.string "active_job_id", limit: 191
    t.integer "attempts", default: 0, null: false
    t.string "contribution_schema_version", limit: 32, null: false
    t.datetime "created_at", null: false
    t.string "declaration_digest", limit: 64, null: false
    t.text "encrypted_arguments", null: false
    t.datetime "enqueued_at"
    t.datetime "finished_at"
    t.string "idempotency_key", limit: 191, null: false
    t.string "job_key", limit: 191, null: false
    t.string "last_enqueue_error_code", limit: 64
    t.string "last_error_code", limit: 64
    t.datetime "lease_expires_at"
    t.integer "lease_seconds", null: false
    t.integer "max_attempts", null: false
    t.string "owner_plugin_id", limit: 191, null: false
    t.string "payload_digest", limit: 64, null: false
    t.integer "payload_digest_version", default: 2, null: false
    t.string "plugin_version", limit: 128, null: false
    t.string "public_id", limit: 36, null: false
    t.datetime "recovery_claimed_at"
    t.integer "requested_wait_seconds", null: false
    t.integer "retry_wait_seconds", null: false
    t.datetime "scheduled_at", null: false
    t.datetime "started_at"
    t.string "status", limit: 32, default: "queued", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_plugin_id", "job_key", "idempotency_key"], name: "idx_plugin_job_runs_owner_job_idempotency", unique: true
    t.index ["owner_plugin_id", "status", "scheduled_at"], name: "idx_plugin_job_runs_owner_status_schedule"
    t.index ["public_id"], name: "index_plugin_job_runs_on_public_id", unique: true
    t.index ["status", "recovery_claimed_at"], name: "idx_plugin_job_runs_status_recovery_claim"
    t.index ["status", "scheduled_at"], name: "idx_plugin_job_runs_status_schedule"
    t.check_constraint "attempts >= 0 AND max_attempts >= 1 AND max_attempts <= 10", name: "plugin_job_runs_attempt_bounds"
    t.check_constraint "declaration_digest::text ~ '^[0-9a-f]{64}$'::text AND payload_digest::text ~ '^[0-9a-f]{64}$'::text", name: "plugin_job_runs_digests"
    t.check_constraint "lease_seconds >= 30 AND lease_seconds <= 3600", name: "plugin_job_runs_lease_bounds"
    t.check_constraint "payload_digest_version = 2", name: "plugin_job_runs_payload_digest_version"
    t.check_constraint "requested_wait_seconds >= 0 AND requested_wait_seconds <= 31536000", name: "plugin_job_runs_requested_wait_bounds"
    t.check_constraint "retry_wait_seconds >= 0 AND retry_wait_seconds <= 86400", name: "plugin_job_runs_retry_wait_bounds"
    t.check_constraint "status::text = ANY (ARRAY['queued'::character varying::text, 'running'::character varying::text, 'retrying'::character varying::text, 'succeeded'::character varying::text, 'failed'::character varying::text, 'paused'::character varying::text, 'cancelled'::character varying::text])", name: "plugin_job_runs_status"
  end

  create_table "plugin_lifecycle_runs", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "actor_id"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.boolean "dry_run", default: false, null: false
    t.string "error_code"
    t.text "error_message"
    t.string "from_version"
    t.bigint "generation_number"
    t.boolean "maintenance_mode", default: false, null: false
    t.string "operation_id", null: false
    t.string "plugin_id"
    t.bigint "plugin_installation_id"
    t.string "recovery_path"
    t.boolean "retryable", default: true, null: false
    t.datetime "started_at", null: false
    t.string "state", default: "running", null: false
    t.string "to_version"
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_plugin_lifecycle_runs_on_actor_id"
    t.index ["operation_id"], name: "index_plugin_lifecycle_runs_on_operation_id", unique: true
    t.index ["plugin_id", "started_at"], name: "index_plugin_lifecycle_runs_on_plugin_id_and_started_at"
    t.index ["plugin_installation_id"], name: "index_plugin_lifecycle_runs_on_plugin_installation_id"
    t.index ["state", "started_at"], name: "index_plugin_lifecycle_runs_on_state_and_started_at"
  end

  create_table "plugin_lifecycle_steps", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.jsonb "details", default: {}, null: false
    t.string "error_code"
    t.text "error_message"
    t.string "idempotency_key", null: false
    t.bigint "plugin_lifecycle_run_id", null: false
    t.boolean "retryable", default: true, null: false
    t.integer "sequence", null: false
    t.datetime "started_at", null: false
    t.string "state", null: false
    t.string "step_key", null: false
    t.datetime "updated_at", null: false
    t.index ["plugin_lifecycle_run_id", "idempotency_key"], name: "index_plugin_lifecycle_steps_on_run_and_idempotency", unique: true
    t.index ["plugin_lifecycle_run_id", "sequence"], name: "index_plugin_lifecycle_steps_on_run_and_sequence", unique: true
    t.index ["plugin_lifecycle_run_id"], name: "index_plugin_lifecycle_steps_on_plugin_lifecycle_run_id"
    t.index ["state", "started_at"], name: "index_plugin_lifecycle_steps_on_state_and_started_at"
  end

  create_table "plugin_maintenance_windows", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.bigint "actor_id"
    t.datetime "created_at", null: false
    t.datetime "ended_at"
    t.datetime "expires_at", null: false
    t.string "operation_id", null: false
    t.string "plugin_id"
    t.datetime "started_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active", "expires_at"], name: "index_plugin_maintenance_windows_on_active_and_expiry"
    t.index ["actor_id"], name: "index_plugin_maintenance_windows_on_actor_id"
    t.index ["operation_id"], name: "index_plugin_maintenance_windows_on_operation_id", unique: true
    t.check_constraint "expires_at > started_at", name: "plugin_maintenance_windows_valid_interval"
  end

  create_table "plugin_outbound_deliveries", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.text "encrypted_destination"
    t.text "encrypted_payload", null: false
    t.text "encrypted_secret"
    t.string "idempotency_key", null: false
    t.string "kind", null: false
    t.string "last_error_code"
    t.integer "last_http_status"
    t.integer "lock_version", default: 0, null: false
    t.integer "max_attempts", default: 5, null: false
    t.datetime "next_attempt_at"
    t.string "owner_plugin_id", null: false
    t.string "payload_digest", null: false
    t.string "public_id", null: false
    t.text "response_summary"
    t.string "status", default: "queued", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["owner_plugin_id", "kind", "idempotency_key"], name: "index_plugin_deliveries_on_owner_kind_idempotency", unique: true
    t.index ["public_id"], name: "index_plugin_outbound_deliveries_on_public_id", unique: true
    t.index ["status", "next_attempt_at"], name: "index_plugin_outbound_deliveries_on_status_and_next_attempt_at"
    t.index ["user_id"], name: "index_plugin_outbound_deliveries_on_user_id"
  end

  create_table "plugin_process_acks", force: :cascade do |t|
    t.datetime "acked_at", null: false
    t.datetime "created_at", null: false
    t.string "error_code"
    t.text "error_message"
    t.string "hostname"
    t.datetime "last_seen_at", null: false
    t.bigint "plugin_generation_id", null: false
    t.jsonb "plugin_versions", default: {}, null: false
    t.string "process_kind", null: false
    t.integer "process_pid"
    t.string "process_uid", null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["plugin_generation_id", "process_uid"], name: "index_plugin_process_acks_on_generation_and_process", unique: true
    t.index ["plugin_generation_id"], name: "index_plugin_process_acks_on_plugin_generation_id"
    t.index ["process_uid", "last_seen_at"], name: "index_plugin_process_acks_on_process_uid_and_last_seen_at"
    t.index ["status", "last_seen_at"], name: "index_plugin_process_acks_on_status_and_last_seen_at"
  end

  create_table "plugin_releases", force: :cascade do |t|
    t.string "api_version", null: false
    t.datetime "created_at", null: false
    t.jsonb "diagnostics", default: [], null: false
    t.string "health", default: "untracked", null: false
    t.jsonb "manifest_descriptor", default: {}, null: false
    t.string "manifest_sha256", null: false
    t.datetime "observed_at", null: false
    t.string "operation_id"
    t.string "package_digest_source", null: false
    t.string "package_sha256", null: false
    t.string "plugin_id", null: false
    t.bigint "plugin_installation_id", null: false
    t.string "state", null: false
    t.datetime "updated_at", null: false
    t.string "version", null: false
    t.index ["health", "observed_at"], name: "index_plugin_releases_on_health_and_observed_at"
    t.index ["plugin_id", "state"], name: "index_plugin_releases_on_plugin_id_and_state"
    t.index ["plugin_installation_id", "version", "package_sha256"], name: "idx_plugin_releases_identity", unique: true
    t.index ["plugin_installation_id"], name: "idx_plugin_releases_current", unique: true, where: "((state)::text = ANY (ARRAY[('active'::character varying)::text, ('disabled'::character varying)::text, ('uninstalled'::character varying)::text]))"
    t.index ["plugin_installation_id"], name: "index_plugin_releases_on_plugin_installation_id"
    t.check_constraint "health::text = ANY (ARRAY['healthy'::character varying::text, 'changed'::character varying::text, 'missing'::character varying::text, 'unavailable'::character varying::text, 'untracked'::character varying::text])", name: "plugin_releases_health"
    t.check_constraint "package_digest_source::text = ANY (ARRAY['receipt'::character varying::text, 'derived'::character varying::text])", name: "plugin_releases_digest_source"
    t.check_constraint "state::text = ANY (ARRAY['active'::character varying::text, 'disabled'::character varying::text, 'rollback'::character varying::text, 'uninstalled'::character varying::text])", name: "plugin_releases_state"
  end

  create_table "plugin_setting_versions", force: :cascade do |t|
    t.bigint "actor_id"
    t.string "change_kind", limit: 32, null: false
    t.datetime "created_at", null: false
    t.text "encrypted_values", null: false
    t.bigint "migration_source_id"
    t.string "plugin_id", limit: 191, null: false
    t.bigint "revision", null: false
    t.bigint "rollback_source_id"
    t.string "schema_digest", limit: 64, null: false
    t.string "schema_version", limit: 32, null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_plugin_setting_versions_on_actor_id"
    t.index ["migration_source_id"], name: "index_plugin_setting_versions_on_migration_source_id"
    t.index ["plugin_id", "schema_version", "created_at"], name: "idx_plugin_settings_namespace_version_created"
    t.index ["plugin_id", "schema_version", "revision"], name: "idx_plugin_settings_namespace_version_revision", unique: true
    t.index ["rollback_source_id"], name: "index_plugin_setting_versions_on_rollback_source_id"
    t.check_constraint "change_kind::text = ANY (ARRAY['update'::character varying::text, 'migration'::character varying::text, 'rollback'::character varying::text])", name: "plugin_setting_versions_change_kind"
    t.check_constraint "revision > 0", name: "plugin_setting_versions_positive_revision"
    t.check_constraint "schema_digest::text ~ '^[0-9a-f]{64}$'::text", name: "plugin_setting_versions_schema_digest"
  end

  create_table "plugin_storage_objects", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum_sha256", null: false
    t.string "content_type", null: false
    t.datetime "created_at", null: false
    t.text "encrypted_metadata", null: false
    t.datetime "expires_at"
    t.string "key", limit: 512, null: false
    t.integer "lock_version", default: 0, null: false
    t.string "owner_plugin_id", null: false
    t.string "public_id", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_plugin_storage_objects_on_expires_at"
    t.index ["owner_plugin_id", "key"], name: "index_plugin_storage_objects_on_owner_plugin_id_and_key", unique: true
    t.index ["public_id"], name: "index_plugin_storage_objects_on_public_id", unique: true
  end

  create_table "rate_limit_counters", force: :cascade do |t|
    t.bigint "blocked_count", default: 0, null: false
    t.integer "count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "key", null: false
    t.datetime "last_blocked_at"
    t.datetime "updated_at", null: false
    t.datetime "window_start", null: false
    t.index ["expires_at"], name: "index_rate_limit_counters_on_expires_at"
    t.index ["key"], name: "index_rate_limit_counters_on_key", unique: true
    t.index ["key"], name: "index_rate_limit_counters_on_key_pattern", opclass: :varchar_pattern_ops
    t.index ["last_blocked_at"], name: "index_rate_limit_counters_on_last_blocked_at"
    t.index ["window_start"], name: "index_rate_limit_counters_on_window_start"
    t.check_constraint "blocked_count >= 0", name: "rate_limit_counters_blocked_count_nonnegative"
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
    t.boolean "developer_mode", default: false, null: false
    t.datetime "expires_at", null: false
    t.string "ip_address"
    t.datetime "last_active_at"
    t.boolean "remember_me", default: false, null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.bigint "user_id", null: false
    t.index ["developer_mode"], name: "index_sessions_on_developer_mode"
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
    t.string "gift_note", limit: 200
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
    t.datetime "abandoned_reminder_sent_at"
    t.datetime "abandoned_second_reminder_sent_at"
    t.datetime "created_at", null: false
    t.string "recovery_token"
    t.string "session_token"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["recovery_token"], name: "index_store_carts_on_recovery_token", unique: true
    t.index ["session_token"], name: "index_store_carts_on_session_token", unique: true
    t.index ["user_id"], name: "index_store_carts_on_user_id"
  end

  create_table "store_categories", force: :cascade do |t|
    t.string "color_hex"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "icon"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.jsonb "seo", default: {}, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_store_categories_on_slug", unique: true
  end

  create_table "store_coupons", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.jsonb "category_ids", default: [], null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "discount_type", null: false
    t.integer "discount_value", null: false
    t.datetime "ends_at"
    t.boolean "first_order_only", default: false, null: false
    t.boolean "free_shipping", default: false, null: false
    t.integer "max_discount_cents"
    t.integer "min_amount_cents", default: 0, null: false
    t.integer "per_user_limit"
    t.jsonb "product_ids", default: [], null: false
    t.datetime "starts_at"
    t.datetime "updated_at", null: false
    t.integer "usage_limit"
    t.integer "used_count", default: 0, null: false
    t.index ["code"], name: "index_store_coupons_on_code", unique: true
  end

  create_table "store_credit_transactions", force: :cascade do |t|
    t.bigint "actor_id"
    t.integer "amount_cents", null: false
    t.string "authorization_digest", limit: 64
    t.integer "balance_after_cents"
    t.integer "balance_before_cents"
    t.datetime "created_at", null: false
    t.string "note"
    t.string "request_fingerprint", limit: 64
    t.string "request_id", limit: 36
    t.bigint "store_order_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["actor_id"], name: "index_store_credit_transactions_on_actor_id"
    t.index ["authorization_digest"], name: "idx_store_credit_transactions_authorization", unique: true, where: "(authorization_digest IS NOT NULL)"
    t.index ["request_id"], name: "idx_store_credit_transactions_request_id", unique: true, where: "(request_id IS NOT NULL)"
    t.index ["store_order_id"], name: "index_store_credit_transactions_on_store_order_id"
    t.index ["user_id"], name: "index_store_credit_transactions_on_user_id"
    t.check_constraint "authorization_digest IS NULL OR authorization_digest::text ~ '^[0-9a-f]{64}$'::text", name: "chk_store_credit_transactions_authorization_digest"
    t.check_constraint "request_fingerprint IS NULL OR request_fingerprint::text ~ '^[0-9a-f]{64}$'::text", name: "chk_store_credit_transactions_request_fingerprint"
    t.check_constraint "request_id IS NULL AND request_fingerprint IS NULL AND authorization_digest IS NULL AND balance_before_cents IS NULL AND balance_after_cents IS NULL OR request_id IS NOT NULL AND request_fingerprint IS NOT NULL AND authorization_digest IS NOT NULL AND balance_before_cents IS NOT NULL AND balance_after_cents IS NOT NULL", name: "chk_store_credit_transactions_adjustment_metadata"
    t.check_constraint "request_id IS NULL OR request_id::text ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'::text", name: "chk_store_credit_transactions_request_id"
  end

  create_table "store_dispute_events", force: :cascade do |t|
    t.bigint "actor_id"
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.string "from_status"
    t.string "idempotency_key", null: false
    t.jsonb "metadata", default: {}, null: false
    t.text "note"
    t.string "payload_digest", limit: 64
    t.bigint "payment_webhook_event_id"
    t.string "provider_event_id"
    t.datetime "provider_occurred_at"
    t.bigint "provider_sequence"
    t.string "provider_status"
    t.string "request_id"
    t.string "source", null: false
    t.bigint "store_dispute_id", null: false
    t.string "to_status"
    t.index ["actor_id"], name: "index_store_dispute_events_on_actor_id"
    t.index ["idempotency_key"], name: "index_store_dispute_events_on_idempotency_key", unique: true
    t.index ["payment_webhook_event_id"], name: "index_store_dispute_events_on_payment_webhook_event_id"
    t.index ["provider_event_id"], name: "index_store_dispute_events_on_provider_event_id"
    t.index ["request_id"], name: "index_store_dispute_events_on_request_id"
    t.index ["store_dispute_id", "created_at"], name: "idx_store_dispute_events_timeline"
    t.index ["store_dispute_id"], name: "index_store_dispute_events_on_store_dispute_id"
    t.check_constraint "payload_digest IS NULL OR payload_digest::text ~ '^[0-9a-f]{64}$'::text", name: "chk_store_dispute_events_digest"
    t.check_constraint "source::text = ANY (ARRAY['channel'::character varying::text, 'manual'::character varying::text, 'policy'::character varying::text, 'system'::character varying::text])", name: "chk_store_dispute_events_source"
  end

  create_table "store_dispute_evidence", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.text "content"
    t.string "content_type", default: "text/plain", null: false
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "idempotency_key", null: false
    t.string "provider_reference"
    t.string "public_id", null: false
    t.datetime "purged_at"
    t.datetime "retention_until"
    t.string "sha256", limit: 64, null: false
    t.bigint "store_dispute_id", null: false
    t.string "submission_status", default: "submitted", null: false
    t.datetime "submitted_at", null: false
    t.bigint "submitted_by_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_store_dispute_evidence_on_idempotency_key", unique: true
    t.index ["public_id"], name: "index_store_dispute_evidence_on_public_id", unique: true
    t.index ["retention_until", "purged_at"], name: "idx_store_dispute_evidence_retention"
    t.index ["store_dispute_id"], name: "index_store_dispute_evidence_on_store_dispute_id"
    t.index ["submitted_by_id"], name: "index_store_dispute_evidence_on_submitted_by_id"
    t.check_constraint "byte_size >= 0", name: "chk_store_dispute_evidence_size"
    t.check_constraint "sha256::text ~ '^[0-9a-f]{64}$'::text", name: "chk_store_dispute_evidence_digest"
    t.check_constraint "submission_status::text = ANY (ARRAY['submitted'::character varying::text, 'failed'::character varying::text, 'purged'::character varying::text])", name: "chk_store_dispute_evidence_status"
  end

  create_table "store_dispute_rights_actions", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "actor_id"
    t.jsonb "after_state", default: {}, null: false
    t.jsonb "before_state", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "idempotency_key", null: false
    t.jsonb "metadata", default: {}, null: false
    t.text "reason"
    t.bigint "store_dispute_id", null: false
    t.bigint "subject_id", null: false
    t.string "subject_type", null: false
    t.index ["actor_id"], name: "index_store_dispute_rights_actions_on_actor_id"
    t.index ["idempotency_key"], name: "index_store_dispute_rights_actions_on_idempotency_key", unique: true
    t.index ["store_dispute_id", "subject_type", "subject_id"], name: "idx_store_dispute_rights_subject"
    t.index ["store_dispute_id"], name: "index_store_dispute_rights_actions_on_store_dispute_id"
    t.index ["subject_type", "subject_id"], name: "index_store_dispute_rights_actions_on_subject"
    t.check_constraint "action::text = ANY (ARRAY['freeze'::character varying::text, 'revoke'::character varying::text, 'restore'::character varying::text])", name: "chk_store_dispute_rights_action"
  end

  create_table "store_disputes", force: :cascade do |t|
    t.datetime "accepted_loss_at"
    t.bigint "accepted_loss_by_id"
    t.integer "amount_cents", null: false
    t.bigint "assigned_to_id"
    t.datetime "closed_at"
    t.bigint "closed_by_id"
    t.datetime "created_at", null: false
    t.string "currency", null: false
    t.datetime "evidence_due_at"
    t.string "kind", default: "dispute", null: false
    t.datetime "latest_provider_event_at"
    t.string "latest_provider_event_id"
    t.bigint "latest_provider_sequence"
    t.boolean "legal_hold", default: false, null: false
    t.integer "liability_cents", default: 0, null: false
    t.integer "lock_version", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.integer "offset_cents", default: 0, null: false
    t.bigint "payment_record_id", null: false
    t.string "provider", null: false
    t.string "provider_dispute_id", null: false
    t.string "provider_status"
    t.string "public_id", null: false
    t.string "reason_code"
    t.string "resolution"
    t.datetime "retention_until"
    t.string "rights_status", default: "unchanged", null: false
    t.string "risk_level", default: "high", null: false
    t.string "status", default: "open", null: false
    t.bigint "store_order_id", null: false
    t.datetime "updated_at", null: false
    t.index ["accepted_loss_by_id"], name: "index_store_disputes_on_accepted_loss_by_id"
    t.index ["assigned_to_id", "status"], name: "idx_store_disputes_assignee_status"
    t.index ["assigned_to_id"], name: "index_store_disputes_on_assigned_to_id"
    t.index ["closed_by_id"], name: "index_store_disputes_on_closed_by_id"
    t.index ["payment_record_id"], name: "index_store_disputes_on_payment_record_id"
    t.index ["provider", "provider_dispute_id"], name: "idx_store_disputes_provider_identity", unique: true
    t.index ["public_id"], name: "index_store_disputes_on_public_id", unique: true
    t.index ["retention_until", "legal_hold"], name: "idx_store_disputes_retention"
    t.index ["risk_level", "status"], name: "idx_store_disputes_risk_status"
    t.index ["status", "evidence_due_at"], name: "idx_store_disputes_status_due"
    t.index ["store_order_id"], name: "index_store_disputes_on_store_order_id"
    t.check_constraint "amount_cents > 0 AND liability_cents >= 0 AND offset_cents >= 0 AND (liability_cents + offset_cents) = amount_cents", name: "chk_store_disputes_amount_conservation"
    t.check_constraint "kind::text = ANY (ARRAY['dispute'::character varying::text, 'chargeback'::character varying::text])", name: "chk_store_disputes_kind"
    t.check_constraint "resolution IS NULL OR (resolution::text = ANY (ARRAY['won'::character varying::text, 'lost'::character varying::text, 'withdrawn'::character varying::text, 'accepted_loss'::character varying::text]))", name: "chk_store_disputes_resolution"
    t.check_constraint "rights_status::text = ANY (ARRAY['unchanged'::character varying::text, 'frozen'::character varying::text, 'revoked'::character varying::text, 'restored'::character varying::text])", name: "chk_store_disputes_rights_status"
    t.check_constraint "risk_level::text = ANY (ARRAY['low'::character varying::text, 'medium'::character varying::text, 'high'::character varying::text, 'critical'::character varying::text])", name: "chk_store_disputes_risk"
    t.check_constraint "status::text = ANY (ARRAY['open'::character varying::text, 'evidence_required'::character varying::text, 'evidence_submitted'::character varying::text, 'under_review'::character varying::text, 'won'::character varying::text, 'lost'::character varying::text, 'withdrawn'::character varying::text, 'closed'::character varying::text])", name: "chk_store_disputes_status"
  end

  create_table "store_finance_document_events", force: :cascade do |t|
    t.bigint "actor_id"
    t.jsonb "after_state", default: {}, null: false
    t.jsonb "before_state", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.jsonb "metadata", default: {}, null: false
    t.text "reason"
    t.string "request_id"
    t.bigint "store_finance_document_id", null: false
    t.index ["actor_id"], name: "index_store_finance_document_events_on_actor_id"
    t.index ["request_id"], name: "index_store_finance_document_events_on_request_id", unique: true, where: "(request_id IS NOT NULL)"
    t.index ["store_finance_document_id", "created_at"], name: "idx_finance_document_events_timeline"
    t.index ["store_finance_document_id"], name: "idx_finance_document_events_document"
    t.check_constraint "event_type::text = ANY (ARRAY['issued'::character varying::text, 'superseded'::character varying::text, 'voided'::character varying::text])", name: "chk_finance_document_events_type"
  end

  create_table "store_finance_documents", force: :cascade do |t|
    t.string "channel", null: false
    t.jsonb "content_snapshot", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "currency", null: false
    t.string "document_kind", null: false
    t.string "document_number", null: false
    t.integer "gross_amount_cents", null: false
    t.datetime "issued_at", null: false
    t.integer "lock_version", default: 0, null: false
    t.integer "net_amount_cents", null: false
    t.string "public_id", null: false
    t.datetime "retention_until", null: false
    t.string "source_digest", null: false
    t.string "status", default: "issued", null: false
    t.bigint "store_finance_tax_snapshot_id", null: false
    t.bigint "store_order_id", null: false
    t.bigint "store_refund_id"
    t.datetime "superseded_at"
    t.bigint "supersedes_id"
    t.integer "tax_amount_cents", null: false
    t.datetime "updated_at", null: false
    t.integer "version", default: 1, null: false
    t.datetime "voided_at"
    t.index ["channel", "currency", "issued_at"], name: "idx_finance_documents_channel_currency"
    t.index ["document_kind", "status", "issued_at"], name: "idx_finance_documents_kind_status_time"
    t.index ["document_number", "version"], name: "idx_finance_documents_number_version", unique: true
    t.index ["public_id"], name: "index_store_finance_documents_on_public_id", unique: true
    t.index ["retention_until"], name: "index_store_finance_documents_on_retention_until"
    t.index ["store_finance_tax_snapshot_id"], name: "idx_finance_documents_tax_snapshot"
    t.index ["store_order_id", "document_kind", "version"], name: "idx_finance_documents_order_kind_version", unique: true, where: "((document_kind)::text = 'invoice'::text)"
    t.index ["store_order_id", "document_kind"], name: "idx_finance_documents_current_invoice", unique: true, where: "(((document_kind)::text = 'invoice'::text) AND ((status)::text = 'issued'::text))"
    t.index ["store_order_id"], name: "index_store_finance_documents_on_store_order_id"
    t.index ["store_refund_id", "document_kind", "version"], name: "idx_finance_documents_refund_kind_version", unique: true, where: "(store_refund_id IS NOT NULL)"
    t.index ["store_refund_id", "document_kind"], name: "idx_finance_documents_current_refund", unique: true, where: "((store_refund_id IS NOT NULL) AND ((document_kind)::text = 'refund_receipt'::text) AND ((status)::text = 'issued'::text))"
    t.index ["store_refund_id"], name: "index_store_finance_documents_on_store_refund_id"
    t.index ["supersedes_id"], name: "idx_finance_documents_supersedes"
    t.check_constraint "(net_amount_cents + tax_amount_cents) = gross_amount_cents", name: "chk_finance_document_conservation"
    t.check_constraint "document_kind::text = 'invoice'::text AND store_refund_id IS NULL OR document_kind::text = 'refund_receipt'::text AND store_refund_id IS NOT NULL", name: "chk_finance_document_source"
    t.check_constraint "document_kind::text = ANY (ARRAY['invoice'::character varying::text, 'refund_receipt'::character varying::text])", name: "chk_finance_documents_kind"
    t.check_constraint "net_amount_cents >= 0 AND tax_amount_cents >= 0 AND gross_amount_cents >= 0", name: "chk_finance_document_amounts"
    t.check_constraint "status::text = ANY (ARRAY['issued'::character varying::text, 'superseded'::character varying::text, 'voided'::character varying::text])", name: "chk_finance_documents_status"
  end

  create_table "store_finance_export_events", force: :cascade do |t|
    t.bigint "actor_id"
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.integer "progress_percent", null: false
    t.string "request_id"
    t.string "status", null: false
    t.bigint "store_finance_export_id", null: false
    t.index ["actor_id"], name: "index_store_finance_export_events_on_actor_id"
    t.index ["store_finance_export_id", "created_at"], name: "idx_finance_export_events_timeline"
    t.index ["store_finance_export_id"], name: "idx_finance_export_events_export"
    t.check_constraint "progress_percent >= 0 AND progress_percent <= 100", name: "chk_finance_export_events_progress"
    t.check_constraint "status::text = ANY (ARRAY['queued'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'expired'::character varying::text, 'revoked'::character varying::text])", name: "chk_finance_export_events_status"
  end

  create_table "store_finance_exports", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "error_code"
    t.datetime "expires_at"
    t.datetime "failed_at"
    t.string "file_sha256"
    t.jsonb "filters", default: {}, null: false
    t.string "filters_digest", null: false
    t.string "format", default: "csv", null: false
    t.string "idempotency_key", null: false
    t.integer "lock_version", default: 0, null: false
    t.integer "progress_percent", default: 0, null: false
    t.string "public_id", null: false
    t.datetime "requested_at", null: false
    t.bigint "requested_by_id", null: false
    t.datetime "retention_until", null: false
    t.datetime "revoked_at"
    t.integer "row_count"
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.datetime "updated_at", null: false
    t.index ["public_id"], name: "index_store_finance_exports_on_public_id", unique: true
    t.index ["requested_by_id", "idempotency_key"], name: "idx_finance_exports_request_idempotency", unique: true
    t.index ["requested_by_id", "status", "requested_at"], name: "idx_finance_exports_actor_status"
    t.index ["requested_by_id"], name: "index_store_finance_exports_on_requested_by_id"
    t.index ["retention_until"], name: "index_store_finance_exports_on_retention_until"
    t.index ["status", "expires_at"], name: "idx_finance_exports_expiry"
    t.check_constraint "attempts >= 0 AND (row_count IS NULL OR row_count >= 0)", name: "chk_finance_exports_counts"
    t.check_constraint "format::text = 'csv'::text", name: "chk_finance_exports_format"
    t.check_constraint "progress_percent >= 0 AND progress_percent <= 100", name: "chk_finance_exports_progress"
    t.check_constraint "status::text = ANY (ARRAY['queued'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'expired'::character varying::text, 'revoked'::character varying::text])", name: "chk_finance_exports_status"
  end

  create_table "store_finance_tax_snapshots", force: :cascade do |t|
    t.integer "calculation_version", default: 1, null: false
    t.datetime "captured_at", null: false
    t.datetime "created_at", null: false
    t.string "currency", null: false
    t.integer "gross_cents", null: false
    t.string "jurisdiction_country", null: false
    t.string "jurisdiction_region"
    t.jsonb "line_snapshot", default: [], null: false
    t.string "pricing_mode", default: "inclusive", null: false
    t.datetime "retention_until", null: false
    t.string "rounding_mode", default: "half_up", null: false
    t.string "source_digest", null: false
    t.bigint "store_order_id", null: false
    t.integer "tax_cents", null: false
    t.string "tax_code", default: "standard", null: false
    t.integer "tax_rate_bps", null: false
    t.integer "taxable_base_cents", null: false
    t.datetime "updated_at", null: false
    t.index ["jurisdiction_country", "jurisdiction_region", "tax_rate_bps"], name: "idx_finance_tax_snapshots_dimensions"
    t.index ["retention_until"], name: "index_store_finance_tax_snapshots_on_retention_until"
    t.index ["store_order_id"], name: "idx_finance_tax_snapshots_order", unique: true
    t.check_constraint "(taxable_base_cents + tax_cents) = gross_cents", name: "chk_finance_tax_conservation"
    t.check_constraint "pricing_mode::text = 'inclusive'::text AND rounding_mode::text = 'half_up'::text", name: "chk_finance_tax_calculation_contract"
    t.check_constraint "tax_rate_bps >= 0 AND tax_rate_bps <= 100000", name: "chk_finance_tax_rate"
    t.check_constraint "taxable_base_cents >= 0 AND tax_cents >= 0 AND gross_cents >= 0", name: "chk_finance_tax_amounts"
  end

  create_table "store_fulfillment_attempts", force: :cascade do |t|
    t.string "action", default: "dispatch", null: false
    t.bigint "actor_id"
    t.integer "attempt_number", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "error_code"
    t.string "idempotency_key", null: false
    t.datetime "next_retry_at"
    t.text "reason"
    t.jsonb "request_data", default: {}, null: false
    t.string "request_id"
    t.jsonb "response_data", default: {}, null: false
    t.jsonb "result_summary", default: {}, null: false
    t.datetime "started_at"
    t.string "status", null: false
    t.bigint "store_fulfillment_id", null: false
    t.string "trigger", default: "automatic", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_store_fulfillment_attempts_on_actor_id"
    t.index ["idempotency_key"], name: "index_store_fulfillment_attempts_on_idempotency_key", unique: true
    t.index ["request_id"], name: "index_store_fulfillment_attempts_on_request_id"
    t.index ["store_fulfillment_id", "attempt_number"], name: "idx_fulfillment_attempt_number", unique: true
    t.index ["store_fulfillment_id"], name: "index_store_fulfillment_attempts_on_store_fulfillment_id"
  end

  create_table "store_fulfillments", force: :cascade do |t|
    t.integer "attempts_count", default: 0, null: false
    t.text "cancel_reason"
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.string "delivery_id", null: false
    t.datetime "fulfilled_at"
    t.text "last_error"
    t.jsonb "last_result_summary", default: {}, null: false
    t.integer "lock_version", default: 0, null: false
    t.integer "max_attempts", default: 5, null: false
    t.datetime "next_attempt_at"
    t.string "status", default: "pending", null: false
    t.bigint "store_order_id", null: false
    t.bigint "store_order_item_id", null: false
    t.datetime "updated_at", null: false
    t.index ["delivery_id"], name: "index_store_fulfillments_on_delivery_id", unique: true
    t.index ["status", "next_attempt_at"], name: "idx_store_fulfillments_recovery"
    t.index ["store_order_id"], name: "index_store_fulfillments_on_store_order_id"
    t.index ["store_order_item_id"], name: "index_store_fulfillments_on_store_order_item_id", unique: true
  end

  create_table "store_gift_card_transactions", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.integer "balance_after_cents", null: false
    t.datetime "created_at", null: false
    t.bigint "store_gift_card_id", null: false
    t.bigint "store_order_id"
    t.string "transaction_type", null: false
    t.index ["store_gift_card_id", "created_at"], name: "idx_on_store_gift_card_id_created_at_c26b811dd0"
    t.index ["store_gift_card_id"], name: "index_store_gift_card_transactions_on_store_gift_card_id"
    t.index ["store_order_id"], name: "index_store_gift_card_transactions_on_store_order_id"
  end

  create_table "store_gift_cards", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "balance_cents", default: 0, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.string "currency", default: "CNY", null: false
    t.datetime "expires_at"
    t.integer "initial_balance_cents", default: 0, null: false
    t.string "note"
    t.bigint "owner_user_id"
    t.bigint "source_order_item_id"
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_store_gift_cards_on_code", unique: true
    t.index ["created_by_id"], name: "index_store_gift_cards_on_created_by_id"
    t.index ["owner_user_id"], name: "index_store_gift_cards_on_owner_user_id"
    t.index ["source_order_item_id"], name: "index_store_gift_cards_on_source_order_item_id"
  end

  create_table "store_high_risk_operations", force: :cascade do |t|
    t.string "action", limit: 64, null: false
    t.bigint "actor_id", null: false
    t.jsonb "after_state", default: {}, null: false
    t.string "authorization_digest", limit: 64, null: false
    t.jsonb "before_state", default: {}, null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.text "reason", null: false
    t.string "request_fingerprint", limit: 64, null: false
    t.string "request_id", limit: 36, null: false
    t.bigint "resource_id"
    t.string "resource_public_id"
    t.string "resource_type"
    t.jsonb "target_snapshot", default: {}, null: false
    t.bigint "target_user_id"
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_store_high_risk_operations_on_action"
    t.index ["actor_id"], name: "index_store_high_risk_operations_on_actor_id"
    t.index ["authorization_digest"], name: "idx_store_high_risk_operations_authorization", unique: true
    t.index ["request_fingerprint"], name: "idx_store_high_risk_operations_fingerprint"
    t.index ["request_id"], name: "idx_store_high_risk_operations_request", unique: true
    t.index ["resource_type", "resource_id"], name: "idx_store_high_risk_operations_resource"
    t.index ["target_user_id"], name: "index_store_high_risk_operations_on_target_user_id"
    t.check_constraint "authorization_digest::text ~ '^[0-9a-f]{64}$'::text", name: "chk_store_high_risk_operations_authorization"
    t.check_constraint "request_fingerprint::text ~ '^[0-9a-f]{64}$'::text", name: "chk_store_high_risk_operations_fingerprint"
    t.check_constraint "request_id::text ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'::text", name: "chk_store_high_risk_operations_request_id"
  end

  create_table "store_inventory_movements", force: :cascade do |t|
    t.bigint "actor_id"
    t.integer "available_after"
    t.integer "available_delta", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "idempotency_key", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "movement_type", null: false
    t.string "public_id", null: false
    t.integer "quantity", null: false
    t.text "reason"
    t.string "request_id"
    t.integer "reserved_after", default: 0, null: false
    t.integer "reserved_delta", default: 0, null: false
    t.integer "sold_after", default: 0, null: false
    t.integer "sold_delta", default: 0, null: false
    t.bigint "store_inventory_reservation_id"
    t.bigint "store_order_id"
    t.bigint "store_order_item_id"
    t.bigint "target_id", null: false
    t.string "target_type", null: false
    t.index ["actor_id"], name: "index_store_inventory_movements_on_actor_id"
    t.index ["idempotency_key"], name: "index_store_inventory_movements_on_idempotency_key", unique: true
    t.index ["public_id"], name: "index_store_inventory_movements_on_public_id", unique: true
    t.index ["request_id"], name: "index_store_inventory_movements_on_request_id"
    t.index ["store_inventory_reservation_id"], name: "idx_on_store_inventory_reservation_id_fcf435c2a7"
    t.index ["store_order_id"], name: "index_store_inventory_movements_on_store_order_id"
    t.index ["store_order_item_id"], name: "index_store_inventory_movements_on_store_order_item_id"
    t.index ["target_type", "target_id", "created_at"], name: "idx_inventory_movements_target_time"
    t.index ["target_type", "target_id"], name: "index_store_inventory_movements_on_target"
    t.check_constraint "movement_type::text = ANY (ARRAY['reserve'::character varying::text, 'confirm'::character varying::text, 'release'::character varying::text, 'expire'::character varying::text, 'refund'::character varying::text, 'damage'::character varying::text, 'adjustment'::character varying::text, 'recovery'::character varying::text])", name: "chk_inventory_movements_type"
    t.check_constraint "quantity > 0", name: "chk_inventory_movements_quantity"
  end

  create_table "store_inventory_reservations", force: :cascade do |t|
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "idempotency_key", null: false
    t.integer "lock_version", default: 0, null: false
    t.integer "quantity", null: false
    t.string "release_reason"
    t.datetime "released_at"
    t.datetime "reserved_at", null: false
    t.string "status", default: "active", null: false
    t.bigint "store_order_id", null: false
    t.bigint "store_order_item_id", null: false
    t.bigint "target_id", null: false
    t.string "target_type", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_store_inventory_reservations_on_idempotency_key", unique: true
    t.index ["status", "expires_at"], name: "idx_inventory_reservations_expiry"
    t.index ["store_order_id"], name: "index_store_inventory_reservations_on_store_order_id"
    t.index ["store_order_item_id"], name: "idx_inventory_reservations_order_item", unique: true
    t.index ["store_order_item_id"], name: "index_store_inventory_reservations_on_store_order_item_id"
    t.index ["target_type", "target_id", "status"], name: "idx_inventory_reservations_target_status"
    t.index ["target_type", "target_id"], name: "index_store_inventory_reservations_on_target"
    t.check_constraint "quantity > 0", name: "chk_inventory_reservations_quantity"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'confirmed'::character varying::text, 'released'::character varying::text, 'expired'::character varying::text])", name: "chk_inventory_reservations_status"
  end

  create_table "store_membership_types", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "color"
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "display_priority", default: 0, null: false
    t.integer "duration_days"
    t.string "duration_mode", default: "fixed_days", null: false
    t.boolean "game_permission_enabled", default: true, null: false
    t.string "game_permission_mode", default: "website_managed", null: false
    t.jsonb "grant_commands", default: [], null: false
    t.string "icon"
    t.string "luckperms_group"
    t.string "name", null: false
    t.jsonb "revoke_commands", default: [], null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_store_membership_types_on_active"
    t.index ["slug"], name: "index_store_membership_types_on_slug", unique: true
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
    t.integer "stock_restored_quantity", default: 0, null: false
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

  create_table "store_order_staff_notes", force: :cascade do |t|
    t.bigint "author_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.bigint "store_order_id", null: false
    t.datetime "updated_at", null: false
    t.boolean "visible_to_customer", default: false, null: false
    t.index ["author_id"], name: "index_store_order_staff_notes_on_author_id"
    t.index ["store_order_id"], name: "index_store_order_staff_notes_on_store_order_id"
  end

  create_table "store_order_webhook_deliveries", force: :cascade do |t|
    t.integer "attempt_count", default: 1, null: false
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.string "order_public_id"
    t.jsonb "request_payload", default: {}, null: false
    t.text "response_body"
    t.integer "response_code"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.string "url", limit: 2048, null: false
    t.index ["created_at"], name: "index_store_order_webhook_deliveries_on_created_at"
    t.index ["order_public_id"], name: "index_store_order_webhook_deliveries_on_order_public_id"
  end

  create_table "store_orders", force: :cascade do |t|
    t.boolean "coupon_usage_restored", default: false, null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "CNY", null: false
    t.integer "discount_cents", default: 0, null: false
    t.integer "gift_card_amount_cents", default: 0, null: false
    t.integer "gift_card_restored_cents", default: 0, null: false
    t.boolean "gift_wrap", default: false, null: false
    t.integer "gift_wrap_cents", default: 0, null: false
    t.text "notes"
    t.string "order_number", null: false
    t.datetime "payment_reminder_sent_at"
    t.string "public_id", null: false
    t.datetime "review_request_sent_at"
    t.datetime "shipped_at"
    t.jsonb "shipping_address", default: {}, null: false
    t.string "shipping_carrier"
    t.integer "shipping_cents", default: 0, null: false
    t.string "shipping_method"
    t.string "status", default: "pending", null: false
    t.bigint "store_coupon_id"
    t.integer "store_credit_amount_cents", default: 0, null: false
    t.integer "store_credit_restored_cents", default: 0, null: false
    t.bigint "store_gift_card_id"
    t.integer "subtotal_cents", default: 0, null: false
    t.integer "total_cents", default: 0, null: false
    t.string "tracking_number"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["order_number"], name: "index_store_orders_on_order_number", unique: true
    t.index ["payment_reminder_sent_at"], name: "index_store_orders_on_payment_reminder_sent_at"
    t.index ["public_id"], name: "index_store_orders_on_public_id", unique: true
    t.index ["status"], name: "index_store_orders_on_status"
    t.index ["store_coupon_id"], name: "index_store_orders_on_store_coupon_id"
    t.index ["store_gift_card_id"], name: "index_store_orders_on_store_gift_card_id"
    t.index ["user_id"], name: "index_store_orders_on_user_id"
  end

  create_table "store_price_alerts", force: :cascade do |t|
    t.integer "baseline_price_cents", null: false
    t.datetime "created_at", null: false
    t.datetime "notified_at"
    t.bigint "store_product_id", null: false
    t.bigint "store_product_variant_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["store_product_id"], name: "index_store_price_alerts_on_store_product_id"
    t.index ["store_product_variant_id"], name: "index_store_price_alerts_on_store_product_variant_id"
    t.index ["user_id", "store_product_id"], name: "index_store_price_alerts_on_user_id_and_store_product_id", unique: true
    t.index ["user_id"], name: "index_store_price_alerts_on_user_id"
  end

  create_table "store_product_answer_helpful_votes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "store_product_answer_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["store_product_answer_id", "user_id"], name: "index_answer_helpful_votes_on_answer_and_user", unique: true
    t.index ["store_product_answer_id"], name: "idx_on_store_product_answer_id_56a408f7be"
    t.index ["user_id"], name: "index_store_product_answer_helpful_votes_on_user_id"
  end

  create_table "store_product_answers", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.boolean "official", default: false, null: false
    t.bigint "store_product_question_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["store_product_question_id"], name: "index_store_product_answers_on_store_product_question_id"
    t.index ["user_id"], name: "index_store_product_answers_on_user_id"
  end

  create_table "store_product_availability_alerts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "notified_at"
    t.bigint "store_product_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["store_product_id"], name: "index_store_product_availability_alerts_on_store_product_id"
    t.index ["user_id", "store_product_id"], name: "index_availability_alerts_on_user_and_product", unique: true
    t.index ["user_id"], name: "index_store_product_availability_alerts_on_user_id"
  end

  create_table "store_product_prerequisites", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "required_product_id", null: false
    t.string "requirement_mode", default: "ever_purchased", null: false
    t.bigint "store_product_id", null: false
    t.datetime "updated_at", null: false
    t.index ["required_product_id"], name: "index_store_product_prerequisites_on_required_product_id"
    t.index ["store_product_id", "required_product_id"], name: "idx_product_prerequisites_unique", unique: true
    t.index ["store_product_id"], name: "index_store_product_prerequisites_on_store_product_id"
  end

  create_table "store_product_questions", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.string "status", default: "published", null: false
    t.bigint "store_order_item_id"
    t.bigint "store_product_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["store_order_item_id"], name: "index_store_product_questions_on_store_order_item_id"
    t.index ["store_product_id"], name: "index_store_product_questions_on_store_product_id"
    t.index ["user_id"], name: "index_store_product_questions_on_user_id"
  end

  create_table "store_product_variants", force: :cascade do |t|
    t.integer "compare_at_price_cents"
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

  create_table "store_product_views", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "store_product_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.datetime "viewed_at", null: false
    t.index ["store_product_id"], name: "index_store_product_views_on_store_product_id"
    t.index ["user_id", "store_product_id"], name: "index_store_product_views_on_user_id_and_store_product_id", unique: true
    t.index ["user_id", "viewed_at"], name: "index_store_product_views_on_user_id_and_viewed_at"
    t.index ["user_id"], name: "index_store_product_views_on_user_id"
  end

  create_table "store_products", force: :cascade do |t|
    t.boolean "allow_backorder", default: false, null: false
    t.datetime "available_at"
    t.text "changelog"
    t.string "changelog_notified_version"
    t.integer "compare_at_price_cents"
    t.datetime "created_at", null: false
    t.string "currency", default: "CNY", null: false
    t.text "description"
    t.boolean "featured", default: false, null: false
    t.bigint "forum_topic_id"
    t.jsonb "fulfillment_config", default: {}, null: false
    t.jsonb "gallery_urls", default: [], null: false
    t.string "image_url"
    t.integer "maximum_quantity"
    t.jsonb "metadata", default: {}, null: false
    t.integer "minimum_quantity", default: 1, null: false
    t.string "name", null: false
    t.string "prerequisite_match_mode", default: "all", null: false
    t.integer "price_cents", default: 0, null: false
    t.string "product_type", null: false
    t.string "public_id", null: false
    t.integer "purchase_limit"
    t.boolean "requires_shipping", default: false, null: false
    t.jsonb "seo", default: {}, null: false
    t.string "slug", null: false
    t.string "status", default: "draft", null: false
    t.integer "stock"
    t.bigint "store_category_id"
    t.bigint "store_membership_type_id"
    t.text "summary"
    t.datetime "unavailable_at"
    t.datetime "updated_at", null: false
    t.string "version"
    t.integer "view_count", default: 0, null: false
    t.index ["available_at"], name: "index_store_products_on_available_at"
    t.index ["forum_topic_id"], name: "index_store_products_on_forum_topic_id"
    t.index ["public_id"], name: "index_store_products_on_public_id", unique: true
    t.index ["slug"], name: "index_store_products_on_slug", unique: true
    t.index ["store_category_id"], name: "index_store_products_on_store_category_id"
    t.index ["store_membership_type_id"], name: "index_store_products_on_store_membership_type_id"
    t.index ["unavailable_at"], name: "index_store_products_on_unavailable_at"
  end

  create_table "store_refunds", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.bigint "approved_by_id"
    t.datetime "created_at", null: false
    t.bigint "payment_record_id", null: false
    t.datetime "processing_started_at"
    t.datetime "provider_confirmed_at"
    t.string "provider_error_code"
    t.jsonb "provider_metadata", default: {}, null: false
    t.string "provider_refund_id"
    t.string "provider_status"
    t.string "reason"
    t.boolean "requested_by_customer", default: false, null: false
    t.bigint "requested_by_id"
    t.integer "restoration_attempts", default: 0, null: false
    t.datetime "restoration_completed_at"
    t.text "restoration_error"
    t.string "restoration_status", default: "pending", null: false
    t.string "status", default: "pending", null: false
    t.bigint "store_order_id", null: false
    t.datetime "updated_at", null: false
    t.index ["approved_by_id"], name: "index_store_refunds_on_approved_by_id"
    t.index ["payment_record_id"], name: "index_store_refunds_on_payment_record_id"
    t.index ["provider_refund_id"], name: "index_store_refunds_on_provider_refund_id", unique: true, where: "(provider_refund_id IS NOT NULL)"
    t.index ["requested_by_id"], name: "index_store_refunds_on_requested_by_id"
    t.index ["restoration_status", "processing_started_at"], name: "index_store_refunds_on_restoration_recovery"
    t.index ["status", "created_at", "payment_record_id", "id"], name: "idx_store_refunds_reconciliation_local"
    t.index ["status", "processing_started_at"], name: "index_store_refunds_on_status_and_processing_started_at"
    t.index ["store_order_id"], name: "index_store_refunds_on_store_order_id"
    t.check_constraint "amount_cents > 0", name: "store_refunds_amount_cents_positive"
    t.check_constraint "restoration_status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'failed'::character varying::text, 'completed'::character varying::text])", name: "store_refunds_restoration_status_valid"
  end

  create_table "store_review_helpful_votes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "store_review_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["store_review_id", "user_id"], name: "index_review_helpful_votes_on_review_and_user", unique: true
  end

  create_table "store_reviews", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.bigint "forum_post_id"
    t.datetime "merchant_replied_at"
    t.text "merchant_reply"
    t.integer "rating", null: false
    t.string "status", default: "published", null: false
    t.bigint "store_product_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["forum_post_id"], name: "index_store_reviews_on_forum_post_id"
    t.index ["store_product_id", "status"], name: "index_store_reviews_on_store_product_id_and_status"
    t.index ["store_product_id", "user_id"], name: "index_store_reviews_on_store_product_id_and_user_id", unique: true
    t.index ["store_product_id"], name: "index_store_reviews_on_store_product_id"
    t.index ["user_id"], name: "index_store_reviews_on_user_id"
  end

  create_table "store_shipping_addresses", force: :cascade do |t|
    t.string "city", null: false
    t.datetime "created_at", null: false
    t.boolean "default_address", default: false, null: false
    t.string "label", limit: 50
    t.string "line1", null: false
    t.string "line2"
    t.string "name", null: false
    t.string "phone", null: false
    t.string "postal_code"
    t.string "province", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "default_address"], name: "index_store_shipping_addresses_on_user_id_and_default_address"
    t.index ["user_id"], name: "index_store_shipping_addresses_on_user_id"
  end

  create_table "store_stock_alerts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "notified_at"
    t.bigint "store_product_id", null: false
    t.bigint "store_product_variant_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["store_product_id"], name: "index_store_stock_alerts_on_store_product_id"
    t.index ["store_product_variant_id"], name: "index_store_stock_alerts_on_store_product_variant_id"
    t.index ["user_id", "store_product_id", "store_product_variant_id"], name: "index_stock_alerts_on_user_product_variant", unique: true
    t.index ["user_id"], name: "index_store_stock_alerts_on_user_id"
  end

  create_table "store_user_entitlements", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.datetime "revoked_at"
    t.datetime "risk_held_at"
    t.bigint "risk_hold_dispute_id"
    t.bigint "source_order_item_id"
    t.datetime "starts_at", null: false
    t.bigint "store_product_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["expires_at"], name: "index_store_user_entitlements_on_expires_at"
    t.index ["revoked_at"], name: "index_store_user_entitlements_on_revoked_at"
    t.index ["risk_held_at"], name: "index_store_user_entitlements_on_risk_held_at"
    t.index ["risk_hold_dispute_id"], name: "index_store_user_entitlements_on_risk_hold_dispute_id"
    t.index ["source_order_item_id"], name: "idx_user_entitlements_source_order_item_unique", unique: true, where: "(source_order_item_id IS NOT NULL)"
    t.index ["store_product_id"], name: "index_store_user_entitlements_on_store_product_id"
    t.index ["user_id", "store_product_id"], name: "index_store_user_entitlements_on_user_id_and_store_product_id"
    t.index ["user_id"], name: "index_store_user_entitlements_on_user_id"
  end

  create_table "store_user_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.datetime "risk_held_at"
    t.bigint "risk_hold_dispute_id"
    t.string "source", default: "purchase", null: false
    t.bigint "source_order_item_id"
    t.datetime "starts_at", null: false
    t.string "status", default: "active", null: false
    t.bigint "store_membership_type_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["expires_at"], name: "index_store_user_memberships_on_expires_at"
    t.index ["risk_held_at"], name: "index_store_user_memberships_on_risk_held_at"
    t.index ["risk_hold_dispute_id"], name: "index_store_user_memberships_on_risk_hold_dispute_id"
    t.index ["source_order_item_id"], name: "idx_user_memberships_source_order_item_unique", unique: true, where: "(source_order_item_id IS NOT NULL)"
    t.index ["store_membership_type_id"], name: "index_store_user_memberships_on_store_membership_type_id"
    t.index ["user_id", "store_membership_type_id", "status"], name: "idx_user_memberships_user_type_status"
    t.index ["user_id"], name: "index_store_user_memberships_on_user_id"
  end

  create_table "store_wishlist_filter_presets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "filters", default: {}, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "created_at"], name: "index_store_wishlist_filter_presets_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_store_wishlist_filter_presets_on_user_id"
  end

  create_table "store_wishlist_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "note"
    t.bigint "store_product_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "variant_id"
    t.index ["store_product_id"], name: "index_store_wishlist_items_on_store_product_id"
    t.index ["user_id", "store_product_id"], name: "index_store_wishlist_items_on_user_id_and_store_product_id", unique: true
    t.index ["user_id"], name: "index_store_wishlist_items_on_user_id"
    t.index ["variant_id"], name: "index_store_wishlist_items_on_variant_id"
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
    t.datetime "account_closed_at"
    t.string "account_closure_outcome"
    t.string "account_type", default: "member", null: false
    t.datetime "ban_expires_at"
    t.text "ban_reason"
    t.datetime "banned_at"
    t.text "bio"
    t.jsonb "compare_product_ids", default: [], null: false
    t.string "compare_share_token"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.boolean "developer_mode_email_verified", default: false, null: false
    t.string "developer_mode_persona"
    t.boolean "developer_mode_relaxed_password", default: false, null: false
    t.jsonb "dismissed_forum_notice_ids", default: [], null: false
    t.jsonb "dismissed_global_announcement_ids", default: [], null: false
    t.string "display_name"
    t.string "email", null: false
    t.datetime "email_verification_sent_at"
    t.text "email_verification_token_ciphertext"
    t.string "email_verification_token_digest"
    t.boolean "email_verified", default: false, null: false
    t.datetime "email_verified_at"
    t.integer "failed_login_count", default: 0, null: false
    t.string "forum_digest_frequency", default: "none", null: false
    t.datetime "forum_digest_last_sent_at"
    t.boolean "forum_digest_watched_only", default: false, null: false
    t.datetime "forum_dnd_until"
    t.string "forum_flair_color_hex"
    t.boolean "forum_hide_signatures", default: false, null: false
    t.string "forum_pm_policy", default: "everyone", null: false
    t.integer "forum_posts_count", default: 0, null: false
    t.integer "forum_profile_views", default: 0, null: false
    t.text "forum_signature"
    t.string "forum_title"
    t.integer "forum_trust_level_override"
    t.string "forum_watch_email_mode", default: "instant", null: false
    t.datetime "last_seen_at"
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.string "locale", default: "zh-CN", null: false
    t.datetime "locked_until"
    t.string "password_digest", null: false
    t.datetime "password_reset_sent_at"
    t.string "password_reset_token_digest"
    t.bigint "permission_version", default: 0, null: false
    t.string "public_id", null: false
    t.text "recovery_codes_ciphertext"
    t.boolean "require_totp", default: false, null: false
    t.string "status", default: "active", null: false
    t.integer "store_credit_cents", default: 0, null: false
    t.string "time_zone", default: "Asia/Shanghai", null: false
    t.boolean "totp_enabled", default: false, null: false
    t.datetime "totp_recovery_sent_at"
    t.string "totp_recovery_token_digest"
    t.string "totp_secret_ciphertext"
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.string "wishlist_share_token"
    t.index ["account_closure_outcome"], name: "index_users_on_account_closure_outcome"
    t.index ["account_type"], name: "index_users_on_account_type"
    t.index ["compare_share_token"], name: "index_users_on_compare_share_token", unique: true
    t.index ["deleted_at"], name: "index_users_on_deleted_at"
    t.index ["developer_mode_email_verified", "developer_mode_relaxed_password"], name: "index_users_on_developer_mode_credentials"
    t.index ["developer_mode_persona"], name: "idx_users_unique_developer_mode_persona", unique: true, where: "(developer_mode_persona IS NOT NULL)"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["last_seen_at"], name: "index_users_on_last_seen_at"
    t.index ["public_id"], name: "index_users_on_public_id", unique: true
    t.index ["status"], name: "index_users_on_status"
    t.index ["totp_recovery_token_digest"], name: "index_users_on_totp_recovery_token_digest", unique: true, where: "(totp_recovery_token_digest IS NOT NULL)"
    t.index ["username", "display_name"], name: "idx_users_suggest_names_trgm", opclass: :gin_trgm_ops, where: "((status)::text = 'active'::text)", using: :gin
    t.index ["username"], name: "index_users_on_username", unique: true
    t.index ["wishlist_share_token"], name: "index_users_on_wishlist_share_token", unique: true
    t.check_constraint "developer_mode_persona IS NULL OR (developer_mode_persona::text = ANY (ARRAY['owner'::character varying::text, 'moderator'::character varying::text, 'member'::character varying::text]))", name: "users_developer_mode_persona"
    t.check_constraint "permission_version >= 0", name: "users_permission_version_nonnegative"
  end

  create_table "webhook_subscriptions", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.datetime "disabled_at"
    t.string "event", default: "*", null: false
    t.integer "failure_count", default: 0, null: false
    t.datetime "last_delivered_at"
    t.string "last_status"
    t.string "name", null: false
    t.string "secret"
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["active", "event"], name: "index_webhook_subscriptions_on_active_and_event"
  end

  create_table "website_articles", force: :cascade do |t|
    t.string "article_type", default: "news", null: false
    t.bigint "author_id"
    t.text "body"
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
    t.index ["author_id"], name: "index_website_articles_on_author_id"
    t.index ["public_id"], name: "index_website_articles_on_public_id", unique: true
    t.index ["slug"], name: "index_website_articles_on_slug", unique: true
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

  add_foreign_key "admin_module_grants", "users"
  add_foreign_key "admin_module_grants", "users", column: "granted_by_id"
  add_foreign_key "api_keys", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "api_keys", "users", on_delete: :nullify
  add_foreign_key "audit_logs", "users", column: "actor_id"
  add_foreign_key "community_group_memberships", "community_user_groups"
  add_foreign_key "community_group_memberships", "users"
  add_foreign_key "community_push_subscriptions", "users"
  add_foreign_key "data_content_lifecycle_records", "users", column: "deleted_by_id"
  add_foreign_key "data_content_lifecycle_records", "users", column: "purged_by_id"
  add_foreign_key "data_content_lifecycle_records", "users", column: "restored_by_id"
  add_foreign_key "data_retention_holds", "users", column: "created_by_id"
  add_foreign_key "data_retention_holds", "users", column: "released_by_id"
  add_foreign_key "email_bans", "users", column: "banned_by_id"
  add_foreign_key "forum_bookmarks", "forum_posts"
  add_foreign_key "forum_bookmarks", "forum_topics"
  add_foreign_key "forum_bookmarks", "users"
  add_foreign_key "forum_canned_responses", "users", column: "author_id"
  add_foreign_key "forum_check_ins", "users"
  add_foreign_key "forum_content_requests", "forum_posts"
  add_foreign_key "forum_content_requests", "forum_topics"
  add_foreign_key "forum_content_requests", "users"
  add_foreign_key "forum_conversation_participants", "forum_conversations"
  add_foreign_key "forum_conversation_participants", "users"
  add_foreign_key "forum_conversations", "users", column: "creator_id"
  add_foreign_key "forum_email_reply_addresses", "forum_topics"
  add_foreign_key "forum_email_reply_addresses", "users"
  add_foreign_key "forum_email_reply_deliveries", "action_mailbox_inbound_emails", on_delete: :nullify
  add_foreign_key "forum_email_reply_deliveries", "forum_email_reply_addresses"
  add_foreign_key "forum_email_reply_deliveries", "forum_posts"
  add_foreign_key "forum_event_webhook_deliveries", "forum_posts"
  add_foreign_key "forum_event_webhook_deliveries", "forum_topics"
  add_foreign_key "forum_message_revision_backfill_queue", "forum_messages", on_delete: :cascade
  add_foreign_key "forum_message_revisions", "forum_messages", on_delete: :cascade
  add_foreign_key "forum_message_revisions", "users", column: "editor_id"
  add_foreign_key "forum_messages", "forum_conversations"
  add_foreign_key "forum_messages", "users"
  add_foreign_key "forum_moderation_case_notes", "forum_moderation_cases", column: "moderation_case_id"
  add_foreign_key "forum_moderation_case_notes", "users", column: "author_id"
  add_foreign_key "forum_moderation_cases", "forum_sections"
  add_foreign_key "forum_moderation_cases", "users", column: "assignee_id"
  add_foreign_key "forum_moderation_cases", "users", column: "target_user_id"
  add_foreign_key "forum_moderation_operations", "users", column: "actor_id"
  add_foreign_key "forum_mutes", "forum_sections"
  add_foreign_key "forum_mutes", "users"
  add_foreign_key "forum_mutes", "users", column: "created_by_id"
  add_foreign_key "forum_point_accounts", "users"
  add_foreign_key "forum_point_transactions", "forum_point_accounts"
  add_foreign_key "forum_point_transactions", "users"
  add_foreign_key "forum_poll_votes", "forum_polls"
  add_foreign_key "forum_poll_votes", "users"
  add_foreign_key "forum_polls", "forum_topics"
  add_foreign_key "forum_post_attachments", "forum_messages"
  add_foreign_key "forum_post_attachments", "forum_posts"
  add_foreign_key "forum_post_attachments", "users"
  add_foreign_key "forum_post_edits", "forum_posts"
  add_foreign_key "forum_post_edits", "users", column: "editor_id"
  add_foreign_key "forum_posts", "forum_posts", column: "parent_post_id"
  add_foreign_key "forum_posts", "forum_posts", column: "quoted_post_id"
  add_foreign_key "forum_posts", "forum_topics"
  add_foreign_key "forum_posts", "users"
  add_foreign_key "forum_profile_post_comments", "forum_profile_posts", column: "profile_post_id"
  add_foreign_key "forum_profile_post_comments", "users"
  add_foreign_key "forum_profile_posts", "users"
  add_foreign_key "forum_profile_posts", "users", column: "profile_user_id"
  add_foreign_key "forum_reactions", "forum_posts"
  add_foreign_key "forum_reactions", "users"
  add_foreign_key "forum_read_states", "forum_topics"
  add_foreign_key "forum_read_states", "users"
  add_foreign_key "forum_reply_drafts", "forum_topics"
  add_foreign_key "forum_reply_drafts", "users"
  add_foreign_key "forum_report_evidences", "forum_reports"
  add_foreign_key "forum_reports", "users", column: "reporter_id"
  add_foreign_key "forum_reports", "users", column: "reviewer_id"
  add_foreign_key "forum_saved_search_webhook_deliveries", "forum_saved_searches", column: "saved_search_id"
  add_foreign_key "forum_saved_searches", "users"
  add_foreign_key "forum_search_histories", "users"
  add_foreign_key "forum_section_moderators", "forum_sections"
  add_foreign_key "forum_section_moderators", "users"
  add_foreign_key "forum_section_mutes", "forum_sections"
  add_foreign_key "forum_section_mutes", "users"
  add_foreign_key "forum_sections", "forum_categories"
  add_foreign_key "forum_sections", "forum_sections", column: "parent_id"
  add_foreign_key "forum_sections", "users", column: "archived_by_id"
  add_foreign_key "forum_staff_notes", "users"
  add_foreign_key "forum_staff_notes", "users", column: "author_id"
  add_foreign_key "forum_subscriptions", "users"
  add_foreign_key "forum_tag_group_memberships", "forum_tag_groups"
  add_foreign_key "forum_tag_group_memberships", "forum_tags"
  add_foreign_key "forum_tags", "forum_tags", column: "canonical_tag_id"
  add_foreign_key "forum_topic_field_values", "forum_topic_field_definitions"
  add_foreign_key "forum_topic_field_values", "forum_topics"
  add_foreign_key "forum_topic_invites", "forum_topics"
  add_foreign_key "forum_topic_invites", "users"
  add_foreign_key "forum_topic_invites", "users", column: "invited_by_id"
  add_foreign_key "forum_topic_mutes", "forum_topics"
  add_foreign_key "forum_topic_mutes", "users"
  add_foreign_key "forum_topic_reply_bans", "forum_topics"
  add_foreign_key "forum_topic_reply_bans", "users"
  add_foreign_key "forum_topic_reply_bans", "users", column: "created_by_id"
  add_foreign_key "forum_topic_staff_notes", "forum_topics"
  add_foreign_key "forum_topic_staff_notes", "users", column: "author_id"
  add_foreign_key "forum_topic_tags", "forum_tags"
  add_foreign_key "forum_topic_tags", "forum_topics"
  add_foreign_key "forum_topics", "forum_posts", column: "solved_post_id"
  add_foreign_key "forum_topics", "forum_posts", column: "source_post_id"
  add_foreign_key "forum_topics", "forum_sections"
  add_foreign_key "forum_topics", "users"
  add_foreign_key "forum_topics", "users", column: "assigned_to_id"
  add_foreign_key "forum_topics", "users", column: "last_post_user_id"
  add_foreign_key "forum_unread_filter_presets", "users"
  add_foreign_key "forum_uploads", "active_storage_blobs", on_delete: :nullify
  add_foreign_key "forum_uploads", "forum_post_attachments", on_delete: :nullify
  add_foreign_key "forum_uploads", "forum_posts", on_delete: :nullify
  add_foreign_key "forum_uploads", "users"
  add_foreign_key "forum_uploads", "users", column: "manual_review_revoked_by_id", on_delete: :nullify
  add_foreign_key "forum_uploads", "users", column: "manual_reviewed_by_id", on_delete: :nullify
  add_foreign_key "forum_user_badges", "forum_badges"
  add_foreign_key "forum_user_badges", "users"
  add_foreign_key "forum_user_blocks", "users", column: "blocked_id"
  add_foreign_key "forum_user_blocks", "users", column: "blocker_id"
  add_foreign_key "forum_user_field_values", "forum_user_field_definitions"
  add_foreign_key "forum_user_field_values", "users"
  add_foreign_key "forum_user_follows", "users", column: "followed_id"
  add_foreign_key "forum_user_follows", "users", column: "follower_id"
  add_foreign_key "forum_user_ignores", "users", column: "ignored_id"
  add_foreign_key "forum_user_ignores", "users", column: "ignorer_id"
  add_foreign_key "forum_user_silences", "users"
  add_foreign_key "forum_user_silences", "users", column: "created_by_id"
  add_foreign_key "forum_user_warnings", "users"
  add_foreign_key "forum_user_warnings", "users", column: "issuer_id"
  add_foreign_key "identity_data_exports", "users"
  add_foreign_key "installation_locks", "users", column: "locked_by_id"
  add_foreign_key "ip_bans", "users", column: "banned_by_id"
  add_foreign_key "minecraft_connector_tasks", "minecraft_servers"
  add_foreign_key "minecraft_connector_tasks", "store_fulfillments"
  add_foreign_key "minecraft_identities", "minecraft_player_profiles", column: "player_profile_id"
  add_foreign_key "minecraft_identities", "minecraft_servers"
  add_foreign_key "minecraft_identities", "users"
  add_foreign_key "minecraft_identity_links", "minecraft_player_profiles", column: "player_profile_id"
  add_foreign_key "minecraft_identity_links", "users"
  add_foreign_key "minecraft_integration_action_logs", "minecraft_integration_actions", column: "integration_action_id"
  add_foreign_key "minecraft_link_codes", "minecraft_servers"
  add_foreign_key "minecraft_link_codes", "users", column: "used_by_id"
  add_foreign_key "minecraft_node_metric_snapshots", "minecraft_nodes"
  add_foreign_key "minecraft_node_metric_snapshots", "minecraft_servers"
  add_foreign_key "minecraft_node_operation_batches", "minecraft_node_operations"
  add_foreign_key "minecraft_node_operation_batches", "minecraft_nodes"
  add_foreign_key "minecraft_node_operation_target_results", "minecraft_node_operation_batches"
  add_foreign_key "minecraft_node_operation_target_results", "minecraft_servers"
  add_foreign_key "minecraft_node_tasks", "minecraft_nodes"
  add_foreign_key "minecraft_node_tasks", "minecraft_servers"
  add_foreign_key "minecraft_permission_groups", "minecraft_player_profiles", column: "player_profile_id"
  add_foreign_key "minecraft_player_identities", "minecraft_player_profiles", column: "player_profile_id"
  add_foreign_key "minecraft_player_identities", "minecraft_servers", column: "primary_server_id"
  add_foreign_key "minecraft_player_sessions", "minecraft_player_profiles", column: "player_profile_id"
  add_foreign_key "minecraft_player_sessions", "minecraft_servers"
  add_foreign_key "minecraft_primary_account_change_events", "minecraft_identity_links", column: "from_identity_link_id"
  add_foreign_key "minecraft_primary_account_change_events", "minecraft_identity_links", column: "to_identity_link_id"
  add_foreign_key "minecraft_primary_account_change_events", "minecraft_primary_account_change_requests", column: "primary_account_change_request_id"
  add_foreign_key "minecraft_primary_account_change_events", "users"
  add_foreign_key "minecraft_primary_account_change_events", "users", column: "actor_id"
  add_foreign_key "minecraft_primary_account_change_requests", "minecraft_identity_links", column: "source_identity_link_id"
  add_foreign_key "minecraft_primary_account_change_requests", "minecraft_identity_links", column: "target_identity_link_id"
  add_foreign_key "minecraft_primary_account_change_requests", "users"
  add_foreign_key "minecraft_primary_account_change_requests", "users", column: "decided_by_id"
  add_foreign_key "minecraft_primary_account_change_requests", "users", column: "requested_by_id"
  add_foreign_key "minecraft_processed_deliveries", "minecraft_servers"
  add_foreign_key "minecraft_profile_field_values", "minecraft_player_profiles", column: "player_profile_id"
  add_foreign_key "minecraft_server_snapshots", "minecraft_servers"
  add_foreign_key "minecraft_servers", "minecraft_nodes"
  add_foreign_key "minecraft_skin_refresh_requests", "minecraft_player_identities", column: "player_identity_id"
  add_foreign_key "minecraft_skin_refresh_requests", "users", column: "requested_by_id"
  add_foreign_key "notification_preferences", "users"
  add_foreign_key "notifications", "users"
  add_foreign_key "operations_durable_enqueue_attempts", "operations_durable_enqueue_intents", column: "intent_id", on_delete: :restrict
  add_foreign_key "operations_durable_enqueue_events", "operations_durable_enqueue_attempts", column: "attempt_id", on_delete: :restrict
  add_foreign_key "operations_durable_enqueue_events", "operations_durable_enqueue_intents", column: "intent_id", on_delete: :restrict
  add_foreign_key "operations_manual_task_runs", "users", column: "requested_by_id"
  add_foreign_key "payment_attempts", "payment_records"
  add_foreign_key "payment_late_payment_cases", "payment_records"
  add_foreign_key "payment_late_payment_cases", "payment_webhook_events"
  add_foreign_key "payment_late_payment_cases", "store_orders"
  add_foreign_key "payment_late_payment_cases", "users", column: "acknowledged_by_id"
  add_foreign_key "payment_provider_configs", "users", column: "last_connection_tested_by_id"
  add_foreign_key "payment_reconciliation_discrepancies", "payment_reconciliation_runs", column: "run_id"
  add_foreign_key "payment_reconciliation_discrepancies", "payment_records"
  add_foreign_key "payment_reconciliation_discrepancies", "store_orders"
  add_foreign_key "payment_reconciliation_discrepancies", "store_refunds", column: "refund_id"
  add_foreign_key "payment_reconciliation_discrepancies", "users", column: "reviewed_by_id"
  add_foreign_key "payment_reconciliation_observations", "payment_reconciliation_runs", column: "run_id"
  add_foreign_key "payment_records", "store_orders"
  add_foreign_key "payment_webhook_events", "users", column: "last_replayed_by_id"
  add_foreign_key "plugin_contributions", "plugin_releases", on_delete: :cascade
  add_foreign_key "plugin_files", "plugin_releases", on_delete: :cascade
  add_foreign_key "plugin_generations", "plugin_generations", column: "parent_generation_id"
  add_foreign_key "plugin_generations", "users", column: "initiated_by_id"
  add_foreign_key "plugin_lifecycle_runs", "plugin_installations"
  add_foreign_key "plugin_lifecycle_runs", "users", column: "actor_id"
  add_foreign_key "plugin_lifecycle_steps", "plugin_lifecycle_runs"
  add_foreign_key "plugin_maintenance_windows", "users", column: "actor_id"
  add_foreign_key "plugin_outbound_deliveries", "users"
  add_foreign_key "plugin_process_acks", "plugin_generations"
  add_foreign_key "plugin_releases", "plugin_installations", on_delete: :cascade
  add_foreign_key "plugin_setting_versions", "plugin_setting_versions", column: "migration_source_id"
  add_foreign_key "plugin_setting_versions", "plugin_setting_versions", column: "rollback_source_id"
  add_foreign_key "plugin_setting_versions", "users", column: "actor_id"
  add_foreign_key "role_permissions", "permissions"
  add_foreign_key "role_permissions", "roles"
  add_foreign_key "sessions", "users"
  add_foreign_key "store_cart_items", "store_carts"
  add_foreign_key "store_cart_items", "store_product_variants"
  add_foreign_key "store_cart_items", "store_products"
  add_foreign_key "store_carts", "users"
  add_foreign_key "store_credit_transactions", "store_orders"
  add_foreign_key "store_credit_transactions", "users"
  add_foreign_key "store_credit_transactions", "users", column: "actor_id"
  add_foreign_key "store_dispute_events", "payment_webhook_events"
  add_foreign_key "store_dispute_events", "store_disputes"
  add_foreign_key "store_dispute_events", "users", column: "actor_id"
  add_foreign_key "store_dispute_evidence", "store_disputes"
  add_foreign_key "store_dispute_evidence", "users", column: "submitted_by_id"
  add_foreign_key "store_dispute_rights_actions", "store_disputes"
  add_foreign_key "store_dispute_rights_actions", "users", column: "actor_id"
  add_foreign_key "store_disputes", "payment_records"
  add_foreign_key "store_disputes", "store_orders"
  add_foreign_key "store_disputes", "users", column: "accepted_loss_by_id"
  add_foreign_key "store_disputes", "users", column: "assigned_to_id"
  add_foreign_key "store_disputes", "users", column: "closed_by_id"
  add_foreign_key "store_finance_document_events", "store_finance_documents"
  add_foreign_key "store_finance_document_events", "users", column: "actor_id"
  add_foreign_key "store_finance_documents", "store_finance_documents", column: "supersedes_id"
  add_foreign_key "store_finance_documents", "store_finance_tax_snapshots"
  add_foreign_key "store_finance_documents", "store_orders"
  add_foreign_key "store_finance_documents", "store_refunds"
  add_foreign_key "store_finance_export_events", "store_finance_exports"
  add_foreign_key "store_finance_export_events", "users", column: "actor_id"
  add_foreign_key "store_finance_exports", "users", column: "requested_by_id"
  add_foreign_key "store_finance_tax_snapshots", "store_orders"
  add_foreign_key "store_fulfillment_attempts", "store_fulfillments"
  add_foreign_key "store_fulfillment_attempts", "users", column: "actor_id"
  add_foreign_key "store_fulfillments", "store_order_items"
  add_foreign_key "store_fulfillments", "store_orders"
  add_foreign_key "store_gift_card_transactions", "store_gift_cards"
  add_foreign_key "store_gift_card_transactions", "store_orders"
  add_foreign_key "store_gift_cards", "store_order_items", column: "source_order_item_id"
  add_foreign_key "store_gift_cards", "users", column: "created_by_id"
  add_foreign_key "store_gift_cards", "users", column: "owner_user_id"
  add_foreign_key "store_high_risk_operations", "users", column: "actor_id"
  add_foreign_key "store_high_risk_operations", "users", column: "target_user_id"
  add_foreign_key "store_inventory_movements", "store_inventory_reservations"
  add_foreign_key "store_inventory_movements", "store_order_items"
  add_foreign_key "store_inventory_movements", "store_orders"
  add_foreign_key "store_inventory_movements", "users", column: "actor_id"
  add_foreign_key "store_inventory_reservations", "store_order_items"
  add_foreign_key "store_inventory_reservations", "store_orders"
  add_foreign_key "store_order_events", "store_orders"
  add_foreign_key "store_order_events", "users", column: "actor_id"
  add_foreign_key "store_order_items", "store_orders"
  add_foreign_key "store_order_items", "store_product_variants"
  add_foreign_key "store_order_items", "store_products"
  add_foreign_key "store_order_staff_notes", "store_orders"
  add_foreign_key "store_order_staff_notes", "users", column: "author_id"
  add_foreign_key "store_orders", "store_coupons"
  add_foreign_key "store_orders", "store_gift_cards"
  add_foreign_key "store_orders", "users"
  add_foreign_key "store_price_alerts", "store_product_variants"
  add_foreign_key "store_price_alerts", "store_products"
  add_foreign_key "store_price_alerts", "users"
  add_foreign_key "store_product_answer_helpful_votes", "store_product_answers"
  add_foreign_key "store_product_answer_helpful_votes", "users"
  add_foreign_key "store_product_answers", "store_product_questions"
  add_foreign_key "store_product_answers", "users"
  add_foreign_key "store_product_availability_alerts", "store_products"
  add_foreign_key "store_product_availability_alerts", "users"
  add_foreign_key "store_product_prerequisites", "store_products"
  add_foreign_key "store_product_prerequisites", "store_products", column: "required_product_id"
  add_foreign_key "store_product_questions", "store_order_items"
  add_foreign_key "store_product_questions", "store_products"
  add_foreign_key "store_product_questions", "users"
  add_foreign_key "store_product_variants", "store_products"
  add_foreign_key "store_product_views", "store_products"
  add_foreign_key "store_product_views", "users"
  add_foreign_key "store_products", "forum_topics"
  add_foreign_key "store_products", "store_categories"
  add_foreign_key "store_products", "store_membership_types"
  add_foreign_key "store_refunds", "payment_records"
  add_foreign_key "store_refunds", "store_orders"
  add_foreign_key "store_refunds", "users", column: "approved_by_id"
  add_foreign_key "store_refunds", "users", column: "requested_by_id"
  add_foreign_key "store_review_helpful_votes", "store_reviews"
  add_foreign_key "store_review_helpful_votes", "users"
  add_foreign_key "store_reviews", "forum_posts"
  add_foreign_key "store_reviews", "store_products"
  add_foreign_key "store_reviews", "users"
  add_foreign_key "store_shipping_addresses", "users"
  add_foreign_key "store_stock_alerts", "store_product_variants"
  add_foreign_key "store_stock_alerts", "store_products"
  add_foreign_key "store_stock_alerts", "users"
  add_foreign_key "store_user_entitlements", "store_disputes", column: "risk_hold_dispute_id"
  add_foreign_key "store_user_entitlements", "store_order_items", column: "source_order_item_id"
  add_foreign_key "store_user_entitlements", "store_products"
  add_foreign_key "store_user_entitlements", "users"
  add_foreign_key "store_user_memberships", "store_disputes", column: "risk_hold_dispute_id"
  add_foreign_key "store_user_memberships", "store_membership_types"
  add_foreign_key "store_user_memberships", "store_order_items", column: "source_order_item_id"
  add_foreign_key "store_user_memberships", "users"
  add_foreign_key "store_wishlist_filter_presets", "users"
  add_foreign_key "store_wishlist_items", "store_product_variants", column: "variant_id"
  add_foreign_key "store_wishlist_items", "store_products"
  add_foreign_key "store_wishlist_items", "users"
  add_foreign_key "user_roles", "roles"
  add_foreign_key "user_roles", "users"
  add_foreign_key "webhook_subscriptions", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "website_articles", "users", column: "author_id"
  add_foreign_key "website_blocks", "website_pages"
  add_foreign_key "website_nav_items", "website_pages"
  add_foreign_key "website_page_revisions", "users", column: "author_id"
  add_foreign_key "website_page_revisions", "website_pages"
  add_foreign_key "website_pages", "users", column: "author_id"
  add_foreign_key "website_pages", "website_themes"

  # User-defined PostgreSQL trigger functions and triggers.
  # These database invariants must also exist after db:schema:load.
  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE OR REPLACE FUNCTION public.forum_message_revisions_dequeue_backfill()
     RETURNS trigger
     LANGUAGE plpgsql
    AS $function$
    BEGIN
      DELETE FROM forum_message_revision_backfill_queue
      WHERE forum_message_id = NEW.forum_message_id
        AND revision = NEW.revision
        AND body_digest = NEW.content_digest;
      RETURN NEW;
    END;
    $function$;
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE OR REPLACE FUNCTION public.forum_message_revisions_reject_change()
     RETURNS trigger
     LANGUAGE plpgsql
    AS $function$
    BEGIN
      IF TG_OP = 'DELETE' AND NOT EXISTS (
        SELECT 1 FROM forum_messages WHERE id = OLD.forum_message_id
      ) THEN
        RETURN OLD;
      END IF;

      RAISE EXCEPTION 'forum_message_revisions is immutable while its message exists';
    END;
    $function$;
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE OR REPLACE FUNCTION public.forum_messages_prepare_revision_update()
     RETURNS trigger
     LANGUAGE plpgsql
    AS $function$
    BEGIN
      IF NEW.body IS NOT DISTINCT FROM OLD.body
         AND NEW.revision IS NOT DISTINCT FROM OLD.revision THEN
        RETURN NEW;
      END IF;

      IF EXISTS (
        SELECT 1
        FROM forum_message_revision_backfill_queue
        WHERE forum_message_id = OLD.id
      ) THEN
        RAISE EXCEPTION 'forum message has a pending revision snapshot';
      END IF;

      IF NEW.body IS DISTINCT FROM OLD.body AND NEW.revision = OLD.revision THEN
        NEW.revision := OLD.revision + 1;
      END IF;

      IF NEW.revision <> OLD.revision + 1 THEN
        RAISE EXCEPTION 'forum message revision must advance by one';
      END IF;

      RETURN NEW;
    END;
    $function$;
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE OR REPLACE FUNCTION public.forum_messages_queue_revision_backfill()
     RETURNS trigger
     LANGUAGE plpgsql
    AS $function$
    DECLARE
      snapshot_digest text;
    BEGIN
      snapshot_digest := encode(
        digest(convert_to(NEW.body, 'UTF8'), 'sha256'),
        'hex'
      );
      INSERT INTO forum_message_revision_backfill_queue (
        forum_message_id,
        revision,
        body_digest,
        queued_at
      )
      VALUES (NEW.id, NEW.revision, snapshot_digest, CURRENT_TIMESTAMP)
      ON CONFLICT (forum_message_id, revision) DO NOTHING;
      IF NOT FOUND AND NOT EXISTS (
        SELECT 1
        FROM forum_message_revision_backfill_queue
        WHERE forum_message_id = NEW.id
          AND revision = NEW.revision
          AND body_digest = snapshot_digest
      ) THEN
        RAISE EXCEPTION 'forum message revision queue conflict';
      END IF;
      RETURN NEW;
    END;
    $function$;
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE OR REPLACE FUNCTION public.forum_messages_require_current_revision()
     RETURNS trigger
     LANGUAGE plpgsql
    AS $function$
    BEGIN
      IF TG_OP = 'UPDATE'
         AND (
           NEW.body IS DISTINCT FROM OLD.body
           OR NEW.revision IS DISTINCT FROM OLD.revision
         )
         AND NEW.revision <> OLD.revision + 1 THEN
        RAISE EXCEPTION 'forum message body changes require the next revision';
      END IF;

      IF NOT EXISTS (
        SELECT 1
        FROM forum_message_revisions
        WHERE forum_message_id = NEW.id
          AND revision = NEW.revision
          AND content_digest = encode(
            digest(convert_to(NEW.body, 'UTF8'), 'sha256'),
            'hex'
          )
      ) THEN
        RAISE EXCEPTION 'forum message current revision is missing or mismatched';
      END IF;
      IF EXISTS (
        SELECT 1
        FROM forum_message_revision_backfill_queue
        WHERE forum_message_id = NEW.id
          AND revision = NEW.revision
      ) THEN
        RAISE EXCEPTION 'forum message revision was not written in this transaction';
      END IF;
      RETURN NEW;
    END;
    $function$;
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE OR REPLACE FUNCTION public.forum_report_evidences_reject_change()
     RETURNS trigger
     LANGUAGE plpgsql
    AS $function$
    BEGIN
      RAISE EXCEPTION 'forum_report_evidences is append-only';
    END;
    $function$;
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE OR REPLACE FUNCTION public.identity_auth_acquire_exclusive_lock()
     RETURNS trigger
     LANGUAGE plpgsql
    AS $function$
    BEGIN
      PERFORM pg_advisory_xact_lock(5567389519336522823::bigint);
      RETURN NULL;
    END;
    $function$;
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE OR REPLACE FUNCTION public.identity_auth_bump_group_memberships()
     RETURNS trigger
     LANGUAGE plpgsql
    AS $function$
    BEGIN
      IF TG_OP = 'INSERT' THEN
        UPDATE users AS affected
           SET permission_version = affected.permission_version + 1,
               updated_at = CURRENT_TIMESTAMP
         WHERE affected.id IN (SELECT DISTINCT user_id FROM new_rows);
      ELSIF TG_OP = 'UPDATE' THEN
        WITH changed_rows AS (
          SELECT old_rows.user_id AS old_user_id,
                 new_rows.user_id AS new_user_id
            FROM old_rows
            INNER JOIN new_rows ON new_rows.id = old_rows.id
           WHERE old_rows.user_id IS DISTINCT FROM new_rows.user_id
              OR old_rows.community_user_group_id IS DISTINCT FROM new_rows.community_user_group_id
        ), affected_users AS (
          SELECT old_user_id AS user_id FROM changed_rows
          UNION
          SELECT new_user_id AS user_id FROM changed_rows
        )
        UPDATE users AS affected
           SET permission_version = affected.permission_version + 1,
               updated_at = CURRENT_TIMESTAMP
         WHERE affected.id IN (SELECT user_id FROM affected_users);
      ELSE
        UPDATE users AS affected
           SET permission_version = affected.permission_version + 1,
               updated_at = CURRENT_TIMESTAMP
         WHERE affected.id IN (SELECT DISTINCT user_id FROM old_rows);
      END IF;
      RETURN NULL;
    END;
    $function$;
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE OR REPLACE FUNCTION public.identity_auth_bump_group_permissions()
     RETURNS trigger
     LANGUAGE plpgsql
    AS $function$
    BEGIN
      WITH changed_groups AS (
        SELECT old_rows.id
          FROM old_rows
          INNER JOIN new_rows ON new_rows.id = old_rows.id
         WHERE old_rows.permissions IS DISTINCT FROM new_rows.permissions
      )
      UPDATE users AS affected
         SET permission_version = affected.permission_version + 1,
             updated_at = CURRENT_TIMESTAMP
       WHERE EXISTS (
         SELECT 1
           FROM community_group_memberships
           INNER JOIN changed_groups
             ON changed_groups.id = community_group_memberships.community_user_group_id
          WHERE community_group_memberships.user_id = affected.id
       );
      RETURN NULL;
    END;
    $function$;
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE OR REPLACE FUNCTION public.identity_auth_bump_role_permissions()
     RETURNS trigger
     LANGUAGE plpgsql
    AS $function$
    BEGIN
      IF TG_OP = 'INSERT' THEN
        UPDATE users AS affected
           SET permission_version = affected.permission_version + 1,
               updated_at = CURRENT_TIMESTAMP
         WHERE EXISTS (
           SELECT 1
             FROM user_roles
            WHERE user_roles.user_id = affected.id
              AND user_roles.role_id IN (SELECT DISTINCT role_id FROM new_rows)
         );
      ELSIF TG_OP = 'UPDATE' THEN
        WITH changed_rows AS (
          SELECT old_rows.role_id AS old_role_id,
                 new_rows.role_id AS new_role_id
            FROM old_rows
            INNER JOIN new_rows ON new_rows.id = old_rows.id
           WHERE old_rows.role_id IS DISTINCT FROM new_rows.role_id
              OR old_rows.permission_id IS DISTINCT FROM new_rows.permission_id
        ), affected_roles AS (
          SELECT old_role_id AS role_id FROM changed_rows
          UNION
          SELECT new_role_id AS role_id FROM changed_rows
        )
        UPDATE users AS affected
           SET permission_version = affected.permission_version + 1,
               updated_at = CURRENT_TIMESTAMP
         WHERE EXISTS (
           SELECT 1
             FROM user_roles
            WHERE user_roles.user_id = affected.id
              AND user_roles.role_id IN (SELECT role_id FROM affected_roles)
         );
      ELSE
        UPDATE users AS affected
           SET permission_version = affected.permission_version + 1,
               updated_at = CURRENT_TIMESTAMP
         WHERE EXISTS (
           SELECT 1
             FROM user_roles
            WHERE user_roles.user_id = affected.id
              AND user_roles.role_id IN (SELECT DISTINCT role_id FROM old_rows)
         );
      END IF;
      RETURN NULL;
    END;
    $function$;
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE OR REPLACE FUNCTION public.identity_auth_bump_user_access()
     RETURNS trigger
     LANGUAGE plpgsql
    AS $function$
    BEGIN
      IF OLD.status IS DISTINCT FROM NEW.status
          OR OLD.account_type IS DISTINCT FROM NEW.account_type THEN
        NEW.permission_version := OLD.permission_version + 1;
        NEW.updated_at := CURRENT_TIMESTAMP;
      END IF;
      RETURN NEW;
    END;
    $function$;
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE OR REPLACE FUNCTION public.identity_auth_bump_user_roles()
     RETURNS trigger
     LANGUAGE plpgsql
    AS $function$
    BEGIN
      IF TG_OP = 'INSERT' THEN
        UPDATE users AS affected
           SET permission_version = affected.permission_version + 1,
               updated_at = CURRENT_TIMESTAMP
         WHERE affected.id IN (SELECT DISTINCT user_id FROM new_rows);
      ELSIF TG_OP = 'UPDATE' THEN
        WITH changed_rows AS (
          SELECT old_rows.user_id AS old_user_id,
                 new_rows.user_id AS new_user_id
            FROM old_rows
            INNER JOIN new_rows ON new_rows.id = old_rows.id
           WHERE old_rows.user_id IS DISTINCT FROM new_rows.user_id
              OR old_rows.role_id IS DISTINCT FROM new_rows.role_id
        ), affected_users AS (
          SELECT old_user_id AS user_id FROM changed_rows
          UNION
          SELECT new_user_id AS user_id FROM changed_rows
        )
        UPDATE users AS affected
           SET permission_version = affected.permission_version + 1,
               updated_at = CURRENT_TIMESTAMP
         WHERE affected.id IN (SELECT user_id FROM affected_users);
      ELSE
        UPDATE users AS affected
           SET permission_version = affected.permission_version + 1,
               updated_at = CURRENT_TIMESTAMP
         WHERE affected.id IN (SELECT DISTINCT user_id FROM old_rows);
      END IF;
      RETURN NULL;
    END;
    $function$;
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE OR REPLACE FUNCTION public.operations_durable_attempts_reject_change()
     RETURNS trigger
     LANGUAGE plpgsql
    AS $function$
    BEGIN
      RAISE EXCEPTION 'operations_durable_enqueue_attempts is append-only';
    END;
    $function$;
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE OR REPLACE FUNCTION public.operations_durable_attempts_validate_insert()
     RETURNS trigger
     LANGUAGE plpgsql
    AS $function$
    DECLARE
      current_generation integer;
      expected_attempt_number integer;
      previous_attempt_id bigint;
      previous_attempt_closed boolean;
    BEGIN
      SELECT generation
        INTO current_generation
        FROM operations_durable_enqueue_events
       WHERE intent_id = NEW.intent_id
       ORDER BY sequence DESC
       LIMIT 1;

      SELECT COALESCE(MAX(attempt_number), 0) + 1
        INTO expected_attempt_number
        FROM operations_durable_enqueue_attempts
       WHERE intent_id = NEW.intent_id;

      SELECT id
        INTO previous_attempt_id
        FROM operations_durable_enqueue_attempts
       WHERE intent_id = NEW.intent_id
       ORDER BY attempt_number DESC
       LIMIT 1;

      IF previous_attempt_id IS NOT NULL THEN
        SELECT EXISTS (
          SELECT 1
            FROM operations_durable_enqueue_events
           WHERE attempt_id = previous_attempt_id
             AND event_type IN (
               'attempt_succeeded', 'attempt_skipped', 'attempt_failed', 'lease_expired'
             )
        ) INTO previous_attempt_closed;
        IF NOT previous_attempt_closed THEN
          RAISE EXCEPTION 'durable enqueue previous attempt is still active';
        END IF;
      END IF;

      IF current_generation IS NULL OR NEW.generation <> current_generation THEN
        RAISE EXCEPTION 'durable enqueue attempt generation is stale';
      END IF;
      IF NEW.attempt_number <> expected_attempt_number THEN
        RAISE EXCEPTION 'durable enqueue attempt number is not contiguous';
      END IF;
      RETURN NEW;
    END;
    $function$;
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE OR REPLACE FUNCTION public.operations_durable_events_reject_change()
     RETURNS trigger
     LANGUAGE plpgsql
    AS $function$
    BEGIN
      RAISE EXCEPTION 'operations_durable_enqueue_events is append-only';
    END;
    $function$;
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE OR REPLACE FUNCTION public.operations_durable_events_validate_insert()
     RETURNS trigger
     LANGUAGE plpgsql
    AS $function$
    DECLARE
      previous_sequence integer;
      previous_generation integer;
      previous_event_type text;
      attempt_intent_id bigint;
      attempt_generation integer;
      attempt_lease_expires_at timestamp without time zone;
      effective_lease_expires_at timestamp without time zone;
      latest_attempt_id bigint;
    BEGIN
      SELECT sequence, generation, event_type
        INTO previous_sequence, previous_generation, previous_event_type
        FROM operations_durable_enqueue_events
       WHERE intent_id = NEW.intent_id
       ORDER BY sequence DESC
       LIMIT 1;

      IF previous_sequence IS NULL THEN
        IF NEW.sequence <> 1 OR NEW.generation <> 1 OR NEW.event_type <> 'recorded' THEN
          RAISE EXCEPTION 'durable enqueue ledger must begin with generation one recorded event';
        END IF;
      ELSE
        IF NEW.sequence <> previous_sequence + 1 THEN
          RAISE EXCEPTION 'durable enqueue event sequence is not contiguous';
        END IF;
        IF NEW.event_type = 'reopened' THEN
          IF previous_event_type <> 'dead_lettered' OR NEW.generation <> previous_generation + 1 THEN
            RAISE EXCEPTION 'durable enqueue generation cannot be reopened';
          END IF;
        ELSE
          IF previous_event_type IN ('attempt_succeeded', 'attempt_skipped', 'dead_lettered') THEN
            RAISE EXCEPTION 'durable enqueue terminal generation is closed';
          END IF;
          IF NEW.generation <> previous_generation THEN
            RAISE EXCEPTION 'durable enqueue event generation is stale';
          END IF;
        END IF;
      END IF;

      IF NEW.attempt_id IS NOT NULL THEN
        SELECT intent_id, generation, lease_expires_at
          INTO attempt_intent_id, attempt_generation, attempt_lease_expires_at
          FROM operations_durable_enqueue_attempts
         WHERE id = NEW.attempt_id;
        IF attempt_intent_id IS NULL OR
           attempt_intent_id <> NEW.intent_id OR
           attempt_generation <> NEW.generation THEN
          RAISE EXCEPTION 'durable enqueue event attempt is from another intent or generation';
        END IF;

        IF NEW.event_type = 'attempt_started' THEN
          IF EXISTS (
            SELECT 1
              FROM operations_durable_enqueue_events
             WHERE attempt_id = NEW.attempt_id
               AND event_type IN (
                 'attempt_started', 'lease_renewed',
                 'attempt_succeeded', 'attempt_skipped', 'attempt_failed', 'lease_expired'
               )
          ) THEN
            RAISE EXCEPTION 'durable enqueue attempt was already started';
          END IF;
        ELSIF NEW.event_type = 'lease_renewed' THEN
          IF NOT EXISTS (
            SELECT 1
              FROM operations_durable_enqueue_events
             WHERE attempt_id = NEW.attempt_id
               AND event_type = 'attempt_started'
               AND sequence < NEW.sequence
          ) OR EXISTS (
            SELECT 1
               FROM operations_durable_enqueue_events
              WHERE attempt_id = NEW.attempt_id
                AND event_type IN (
                  'attempt_succeeded', 'attempt_skipped', 'attempt_failed', 'lease_expired'
                )
          ) THEN
            RAISE EXCEPTION 'durable enqueue lease cannot be renewed';
          END IF;
        ELSIF NEW.event_type = 'lease_expired' THEN
          SELECT id
            INTO latest_attempt_id
            FROM operations_durable_enqueue_attempts
           WHERE intent_id = NEW.intent_id
             AND generation = NEW.generation
           ORDER BY attempt_number DESC
           LIMIT 1;
          SELECT GREATEST(
                   attempt_lease_expires_at,
                   COALESCE(MAX(lease_expires_at), attempt_lease_expires_at)
                 )
            INTO effective_lease_expires_at
            FROM operations_durable_enqueue_events
           WHERE attempt_id = NEW.attempt_id
             AND event_type = 'lease_renewed'
             AND sequence < NEW.sequence;
          IF NEW.attempt_id <> latest_attempt_id OR NOT EXISTS (
            SELECT 1
              FROM operations_durable_enqueue_events
             WHERE attempt_id = NEW.attempt_id
               AND event_type = 'attempt_started'
               AND sequence < NEW.sequence
          ) OR EXISTS (
            SELECT 1
              FROM operations_durable_enqueue_events
             WHERE attempt_id = NEW.attempt_id
               AND event_type IN (
                 'attempt_succeeded', 'attempt_skipped', 'attempt_failed', 'lease_expired'
               )
          ) OR NEW.occurred_at < effective_lease_expires_at THEN
            RAISE EXCEPTION 'durable enqueue lease expiry is invalid, premature, or duplicated';
          END IF;
        ELSIF NEW.event_type IN ('attempt_succeeded', 'attempt_skipped', 'attempt_failed') THEN
          IF NOT EXISTS (
            SELECT 1
              FROM operations_durable_enqueue_events
             WHERE attempt_id = NEW.attempt_id
               AND event_type = 'attempt_started'
               AND sequence < NEW.sequence
          ) OR EXISTS (
            SELECT 1
               FROM operations_durable_enqueue_events
              WHERE attempt_id = NEW.attempt_id
                AND event_type IN (
                  'attempt_succeeded', 'attempt_skipped', 'attempt_failed', 'lease_expired'
                )
          ) THEN
            RAISE EXCEPTION 'durable enqueue attempt outcome is invalid or duplicated';
          END IF;
        END IF;
      END IF;
      RETURN NEW;
    END;
    $function$;
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE OR REPLACE FUNCTION public.operations_durable_intents_reject_change()
     RETURNS trigger
     LANGUAGE plpgsql
    AS $function$
    BEGIN
      RAISE EXCEPTION 'operations_durable_enqueue_intents is append-only';
    END;
    $function$;
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE TRIGGER identity_auth_group_memberships_bump_delete AFTER DELETE ON public.community_group_memberships REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION identity_auth_bump_group_memberships();
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE TRIGGER identity_auth_group_memberships_bump_insert AFTER INSERT ON public.community_group_memberships REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION identity_auth_bump_group_memberships();
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE TRIGGER identity_auth_group_memberships_bump_update AFTER UPDATE ON public.community_group_memberships REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION identity_auth_bump_group_memberships();
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE TRIGGER identity_auth_group_memberships_lock BEFORE INSERT OR DELETE OR UPDATE OF user_id, community_user_group_id ON public.community_group_memberships FOR EACH STATEMENT EXECUTE FUNCTION identity_auth_acquire_exclusive_lock();
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE TRIGGER identity_auth_group_permissions_bump_update AFTER UPDATE ON public.community_user_groups REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION identity_auth_bump_group_permissions();
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE TRIGGER identity_auth_group_permissions_lock_update BEFORE UPDATE OF permissions ON public.community_user_groups FOR EACH STATEMENT EXECUTE FUNCTION identity_auth_acquire_exclusive_lock();
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE TRIGGER forum_message_revisions_dequeue_backfill AFTER INSERT ON public.forum_message_revisions FOR EACH ROW EXECUTE FUNCTION forum_message_revisions_dequeue_backfill();
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE TRIGGER forum_message_revisions_immutable BEFORE DELETE OR UPDATE ON public.forum_message_revisions FOR EACH ROW EXECUTE FUNCTION forum_message_revisions_reject_change();
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE TRIGGER forum_messages_prepare_revision_update BEFORE UPDATE OF body, revision ON public.forum_messages FOR EACH ROW EXECUTE FUNCTION forum_messages_prepare_revision_update();
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE TRIGGER forum_messages_queue_revision_backfill AFTER INSERT OR UPDATE OF body, revision ON public.forum_messages FOR EACH ROW EXECUTE FUNCTION forum_messages_queue_revision_backfill();
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE CONSTRAINT TRIGGER forum_messages_require_current_revision AFTER INSERT OR UPDATE OF body, revision ON public.forum_messages DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION forum_messages_require_current_revision();
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE TRIGGER forum_report_evidences_immutable BEFORE DELETE OR UPDATE ON public.forum_report_evidences FOR EACH ROW EXECUTE FUNCTION forum_report_evidences_reject_change();
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE TRIGGER operations_durable_attempts_immutable BEFORE DELETE OR UPDATE ON public.operations_durable_enqueue_attempts FOR EACH ROW EXECUTE FUNCTION operations_durable_attempts_reject_change();
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE TRIGGER operations_durable_attempts_validate BEFORE INSERT ON public.operations_durable_enqueue_attempts FOR EACH ROW EXECUTE FUNCTION operations_durable_attempts_validate_insert();
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE TRIGGER operations_durable_events_immutable BEFORE DELETE OR UPDATE ON public.operations_durable_enqueue_events FOR EACH ROW EXECUTE FUNCTION operations_durable_events_reject_change();
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE TRIGGER operations_durable_events_validate BEFORE INSERT ON public.operations_durable_enqueue_events FOR EACH ROW EXECUTE FUNCTION operations_durable_events_validate_insert();
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE TRIGGER operations_durable_intents_immutable BEFORE DELETE OR UPDATE ON public.operations_durable_enqueue_intents FOR EACH ROW EXECUTE FUNCTION operations_durable_intents_reject_change();
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE TRIGGER identity_auth_role_permissions_bump_delete AFTER DELETE ON public.role_permissions REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION identity_auth_bump_role_permissions();
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE TRIGGER identity_auth_role_permissions_bump_insert AFTER INSERT ON public.role_permissions REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION identity_auth_bump_role_permissions();
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE TRIGGER identity_auth_role_permissions_bump_update AFTER UPDATE ON public.role_permissions REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION identity_auth_bump_role_permissions();
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE TRIGGER identity_auth_role_permissions_lock BEFORE INSERT OR DELETE OR UPDATE OF role_id, permission_id ON public.role_permissions FOR EACH STATEMENT EXECUTE FUNCTION identity_auth_acquire_exclusive_lock();
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE TRIGGER identity_auth_user_roles_bump_delete AFTER DELETE ON public.user_roles REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION identity_auth_bump_user_roles();
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE TRIGGER identity_auth_user_roles_bump_insert AFTER INSERT ON public.user_roles REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION identity_auth_bump_user_roles();
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE TRIGGER identity_auth_user_roles_bump_update AFTER UPDATE ON public.user_roles REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION identity_auth_bump_user_roles();
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE TRIGGER identity_auth_user_roles_lock BEFORE INSERT OR DELETE OR UPDATE OF user_id, role_id ON public.user_roles FOR EACH STATEMENT EXECUTE FUNCTION identity_auth_acquire_exclusive_lock();
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE TRIGGER identity_auth_users_bump_update BEFORE UPDATE OF status, account_type ON public.users FOR EACH ROW EXECUTE FUNCTION identity_auth_bump_user_access();
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE TRIGGER identity_auth_users_lock_delete BEFORE DELETE ON public.users FOR EACH STATEMENT EXECUTE FUNCTION identity_auth_acquire_exclusive_lock();
  MCWEB_SCHEMA_SQL

  execute <<~'MCWEB_SCHEMA_SQL'
    CREATE TRIGGER identity_auth_users_lock_update BEFORE UPDATE OF status, account_type ON public.users FOR EACH STATEMENT EXECUTE FUNCTION identity_auth_acquire_exclusive_lock();
  MCWEB_SCHEMA_SQL


end
