# frozen_string_literal: true

class CreateForumUserRelationshipStates < ActiveRecord::Migration[8.1]
  def change
    # These rows are deliberately retained when a relationship is removed. Without
    # a tombstone, an old DELETE could match a newly-created block (the ABA race).
    create_table :forum_user_relationship_states do |t|
      t.references :actor, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.references :target, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.string :kind, null: false
      t.bigint :revision, null: false, default: 0
      t.boolean :last_desired_state
      t.timestamps

      t.index %i[actor_id target_id kind], unique: true, name: "idx_forum_relationship_state_pair"
      t.check_constraint "revision >= 0", name: "chk_forum_relationship_revision"
      t.check_constraint "kind IN ('block', 'ignore', 'follow')", name: "chk_forum_relationship_kind"
    end
  end
end
