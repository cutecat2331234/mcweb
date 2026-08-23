# frozen_string_literal: true

class CreateForumConversationInvitations < ActiveRecord::Migration[8.1]
  STATUSES = %w[pending accepted declined expired revoked].freeze

  def change
    create_table :forum_conversation_invitations do |t|
      t.string :public_id, null: false, limit: 64
      t.references :forum_conversation,
        null: false,
        foreign_key: { on_delete: :cascade },
        index: { name: "idx_forum_conversation_invitations_conversation" }
      t.references :user,
        null: false,
        foreign_key: { on_delete: :restrict },
        index: { name: "idx_forum_conversation_invitations_user" }
      t.references :invited_by,
        null: false,
        foreign_key: { to_table: :users, on_delete: :restrict },
        index: { name: "idx_forum_conversation_invitations_inviter" }
      t.string :status, null: false, default: "pending"
      t.datetime :expires_at, null: false
      t.datetime :resolved_at
      t.timestamps
    end

    add_index :forum_conversation_invitations,
      :public_id,
      unique: true,
      name: "idx_forum_conversation_invitations_public_id"
    add_index :forum_conversation_invitations,
      %i[forum_conversation_id user_id],
      unique: true,
      where: "status = 'pending'",
      name: "idx_forum_conversation_invitations_one_pending"
    add_index :forum_conversation_invitations,
      %i[user_id status expires_at],
      name: "idx_forum_conversation_invitations_inbox"
    add_index :forum_conversation_invitations,
      %i[status expires_at],
      where: "status = 'pending'",
      name: "idx_forum_conversation_invitations_expiry"

    add_check_constraint :forum_conversation_invitations,
      "status IN (#{STATUSES.map { |status| connection.quote(status) }.join(', ')})",
      name: "forum_conversation_invitations_status"
    add_check_constraint :forum_conversation_invitations,
      "char_length(public_id) BETWEEN 12 AND 64",
      name: "forum_conversation_invitations_public_id_length"
    add_check_constraint :forum_conversation_invitations,
      "(status = 'pending' AND resolved_at IS NULL) OR (status <> 'pending' AND resolved_at IS NOT NULL)",
      name: "forum_conversation_invitations_state_shape"
  end
end
