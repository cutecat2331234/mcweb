class CreateCommunityTables < ActiveRecord::Migration[8.1]
  def change
    create_table :forum_categories do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :forum_categories, :slug, unique: true

    create_table :forum_sections do |t|
      t.references :forum_category, null: false, foreign_key: true
      t.references :parent, foreign_key: { to_table: :forum_sections }
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.integer :position, null: false, default: 0
      t.jsonb :permissions, null: false, default: {}
      t.timestamps
    end
    add_index :forum_sections, [ :forum_category_id, :slug ], unique: true

    create_table :forum_topics do |t|
      t.string :public_id, null: false
      t.references :forum_section, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.integer :replies_count, null: false, default: 0
      t.integer :views_count, null: false, default: 0
      t.boolean :pinned, null: false, default: false
      t.boolean :locked, null: false, default: false
      t.boolean :featured, null: false, default: false
      t.string :status, null: false, default: "published"
      t.datetime :last_posted_at
      t.references :last_post_user, foreign_key: { to_table: :users }
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :forum_topics, :public_id, unique: true
    add_index :forum_topics, [ :forum_section_id, :last_posted_at ]
    add_index :forum_topics, :deleted_at

    create_table :forum_posts do |t|
      t.references :forum_topic, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :floor_number, null: false
      t.text :body, null: false
      t.references :quoted_post, foreign_key: { to_table: :forum_posts }
      t.string :status, null: false, default: "published"
      t.datetime :edited_at
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :forum_posts, [ :forum_topic_id, :floor_number ], unique: true
    add_index :forum_posts, :deleted_at

    create_table :forum_post_edits do |t|
      t.references :forum_post, null: false, foreign_key: true
      t.references :editor, null: false, foreign_key: { to_table: :users }
      t.text :body_before
      t.text :body_after
      t.timestamps
    end

    create_table :forum_reports do |t|
      t.references :reporter, null: false, foreign_key: { to_table: :users }
      t.string :reportable_type, null: false
      t.bigint :reportable_id, null: false
      t.text :reason, null: false
      t.string :status, null: false, default: "pending"
      t.references :reviewer, foreign_key: { to_table: :users }
      t.text :review_note
      t.datetime :reviewed_at
      t.timestamps
    end
    add_index :forum_reports, [ :reportable_type, :reportable_id ]

    create_table :forum_mutes do |t|
      t.references :user, null: false, foreign_key: true
      t.references :forum_section, foreign_key: true
      t.datetime :expires_at
      t.text :reason
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end

    create_table :forum_subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :subscribable_type, null: false
      t.bigint :subscribable_id, null: false
      t.timestamps
    end
    add_index :forum_subscriptions, [ :user_id, :subscribable_type, :subscribable_id ], unique: true

    create_table :forum_reactions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :forum_post, null: false, foreign_key: true
      t.string :emoji, null: false
      t.timestamps
    end
    add_index :forum_reactions, [ :user_id, :forum_post_id, :emoji ], unique: true

    create_table :forum_read_states do |t|
      t.references :user, null: false, foreign_key: true
      t.references :forum_topic, null: false, foreign_key: true
      t.integer :last_read_floor, null: false, default: 0
      t.timestamps
    end
    add_index :forum_read_states, [ :user_id, :forum_topic_id ], unique: true
  end
end
