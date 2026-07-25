# frozen_string_literal: true

class CreateForumEmailReplies < ActiveRecord::Migration[8.1]
  def change
    create_table :action_mailbox_inbound_emails do |t|
      t.integer :status, default: 0, null: false
      t.string :message_id, null: false
      t.string :message_checksum, null: false

      t.timestamps

      t.index %i[message_id message_checksum],
        name: "index_action_mailbox_inbound_emails_uniqueness",
        unique: true
    end

    create_table :forum_email_reply_addresses do |t|
      t.references :user, null: false, foreign_key: true
      t.references :forum_topic, null: false, foreign_key: true
      t.string :purpose, null: false
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.datetime :last_used_at

      t.timestamps

      t.index :token_digest, unique: true
      t.index %i[user_id forum_topic_id expires_at],
        name: "idx_forum_email_reply_addresses_binding"
    end

    create_table :forum_email_reply_deliveries do |t|
      t.references :action_mailbox_inbound_email,
        null: true,
        foreign_key: { on_delete: :nullify },
        index: { unique: true, name: "idx_forum_email_replies_on_inbound" }
      t.references :forum_email_reply_address,
        foreign_key: true,
        index: { name: "idx_forum_email_replies_on_address" }
      t.references :forum_post,
        foreign_key: true,
        index: { name: "idx_forum_email_replies_on_post" }
      t.string :message_id_digest, null: false
      t.string :status, null: false, default: "processing"
      t.string :rejection_reason

      t.timestamps

      t.index :message_id_digest,
        unique: true,
        name: "idx_forum_email_replies_on_message_id"
    end
  end
end
