# frozen_string_literal: true

class AddRound38Features < ActiveRecord::Migration[8.0]
  def change
    add_column :forum_subscriptions, :notification_level, :string, default: "watching", null: false

    create_table :forum_topic_reply_bans do |t|
      t.references :forum_topic, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.text :reason
      t.datetime :expires_at
      t.timestamps
    end
    add_index :forum_topic_reply_bans, [ :forum_topic_id, :user_id ], unique: true, name: "idx_topic_reply_bans_unique"

    create_table :forum_topic_staff_notes do |t|
      t.references :forum_topic, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.text :body, null: false
      t.timestamps
    end

    add_column :forum_sections, :min_trust_level_create, :integer, default: 0, null: false
    add_column :forum_sections, :min_trust_level_reply, :integer, default: 0, null: false

    add_column :forum_conversation_participants, :archived_at, :datetime

    add_column :forum_topics, :global_announcement, :boolean, default: false, null: false
    add_index :forum_topics, :global_announcement, where: "global_announcement = true", name: "index_forum_topics_on_global_announcement"

    add_column :forum_polls, :anonymous, :boolean, default: false, null: false

    add_column :store_product_variants, :compare_at_price_cents, :integer
    add_reference :store_gift_cards, :owner_user, foreign_key: { to_table: :users }
  end
end
