# frozen_string_literal: true

class CreateForumContentRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :forum_content_requests do |t|
      t.references :user, null: false, foreign_key: true
      t.string :operation, null: false, limit: 32
      t.string :key_digest, null: false, limit: 64
      t.string :request_fingerprint, null: false, limit: 64
      t.references :forum_topic, foreign_key: { to_table: :forum_topics }
      t.references :forum_post, foreign_key: { to_table: :forum_posts }
      t.timestamps
    end

    add_index :forum_content_requests,
      %i[user_id operation key_digest],
      unique: true,
      name: "idx_forum_content_requests_idempotency"
    add_check_constraint :forum_content_requests,
      "operation IN ('topic.create', 'post.create')",
      name: "chk_forum_content_requests_operation"
  end
end
