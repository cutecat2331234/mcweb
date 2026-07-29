# frozen_string_literal: true

class CreateForumModerationWorkbench < ActiveRecord::Migration[8.0]
  def change
    create_table :forum_moderation_cases do |t|
      t.references :source, polymorphic: true, null: false, index: false
      t.string :source_kind, null: false
      t.string :status, null: false, default: "open"
      t.string :priority, null: false, default: "normal"
      t.string :risk_level, null: false, default: "medium"
      t.references :forum_section, foreign_key: true
      t.references :target_user, foreign_key: { to_table: :users }
      t.references :assignee, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.text :summary, null: false, default: ""
      t.jsonb :metadata, null: false, default: {}
      t.string :last_action
      t.text :last_reason
      t.datetime :claimed_at
      t.datetime :resolved_at
      t.datetime :source_updated_at, null: false
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :forum_moderation_cases,
      %i[source_type source_id],
      unique: true,
      name: "idx_forum_moderation_cases_source"
    add_index :forum_moderation_cases,
      %i[status priority risk_level updated_at],
      name: "idx_forum_moderation_cases_queue"
    add_index :forum_moderation_cases,
      %i[forum_section_id status],
      name: "idx_forum_moderation_cases_section"
    add_index :forum_moderation_cases,
      %i[assignee_id status],
      name: "idx_forum_moderation_cases_assignee"
    add_index :forum_moderation_cases,
      %i[source_kind source_updated_at],
      name: "idx_forum_moderation_cases_source_kind"
    add_check_constraint :forum_moderation_cases,
      "source_kind IN ('pending_topic', 'pending_post', 'report', 'spam_hit', 'quarantined_attachment', 'user_risk')",
      name: "forum_moderation_cases_source_kind"
    add_check_constraint :forum_moderation_cases,
      "status IN ('open', 'claimed', 'resolved', 'dismissed', 'actioned', 'stale')",
      name: "forum_moderation_cases_status"
    add_check_constraint :forum_moderation_cases,
      "priority IN ('low', 'normal', 'high', 'critical')",
      name: "forum_moderation_cases_priority"
    add_check_constraint :forum_moderation_cases,
      "risk_level IN ('low', 'medium', 'high', 'critical')",
      name: "forum_moderation_cases_risk"

    create_table :forum_moderation_case_notes do |t|
      t.references :moderation_case,
        null: false,
        foreign_key: { to_table: :forum_moderation_cases },
        index: false
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.text :body, null: false
      t.timestamps
    end

    add_index :forum_moderation_case_notes,
      %i[moderation_case_id created_at],
      name: "idx_forum_moderation_case_notes_timeline"

    create_table :forum_moderation_operations do |t|
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.string :action, null: false
      t.string :request_id, null: false
      t.string :request_fingerprint, null: false
      t.string :authorization_digest, null: false
      t.text :reason, null: false
      t.jsonb :target_snapshot, null: false, default: []
      t.jsonb :result_snapshot, null: false, default: []
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :forum_moderation_operations, :request_id, unique: true
    add_index :forum_moderation_operations, :authorization_digest, unique: true
    add_index :forum_moderation_operations,
      %i[actor_id created_at],
      name: "idx_forum_moderation_operations_actor"
    add_check_constraint :forum_moderation_operations,
      "request_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'",
      name: "forum_moderation_operations_request_id"
    add_check_constraint :forum_moderation_operations,
      "char_length(request_fingerprint) = 64 AND char_length(authorization_digest) = 64",
      name: "forum_moderation_operations_digests"
  end
end
