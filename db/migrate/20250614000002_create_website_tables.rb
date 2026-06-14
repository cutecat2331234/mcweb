class CreateWebsiteTables < ActiveRecord::Migration[8.1]
  def change
    create_table :website_themes do |t|
      t.string :name, null: false
      t.string :key, null: false
      t.jsonb :tokens, null: false, default: {}
      t.boolean :active, null: false, default: false
      t.timestamps
    end
    add_index :website_themes, :key, unique: true

    create_table :website_pages do |t|
      t.string :public_id, null: false
      t.string :slug, null: false
      t.string :title, null: false
      t.string :status, null: false, default: "draft"
      t.string :page_type, null: false, default: "custom"
      t.references :website_theme, foreign_key: true
      t.jsonb :seo, null: false, default: {}
      t.jsonb :translations, null: false, default: {}
      t.datetime :published_at
      t.datetime :scheduled_at
      t.references :author, foreign_key: { to_table: :users }
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :website_pages, :public_id, unique: true
    add_index :website_pages, :slug, unique: true
    add_index :website_pages, :status

    create_table :website_page_revisions do |t|
      t.references :website_page, null: false, foreign_key: true
      t.references :author, foreign_key: { to_table: :users }
      t.jsonb :snapshot, null: false, default: {}
      t.integer :revision_number, null: false
      t.timestamps
    end
    add_index :website_page_revisions, [ :website_page_id, :revision_number ], unique: true

    create_table :website_blocks do |t|
      t.references :website_page, null: false, foreign_key: true
      t.string :block_type, null: false
      t.integer :position, null: false, default: 0
      t.jsonb :settings, null: false, default: {}
      t.jsonb :translations, null: false, default: {}
      t.boolean :visible, null: false, default: true
      t.timestamps
    end
    add_index :website_blocks, [ :website_page_id, :position ]

    create_table :website_articles do |t|
      t.string :public_id, null: false
      t.string :article_type, null: false, default: "news"
      t.string :slug, null: false
      t.string :title, null: false
      t.text :summary
      t.string :status, null: false, default: "draft"
      t.jsonb :translations, null: false, default: {}
      t.jsonb :seo, null: false, default: {}
      t.datetime :published_at
      t.datetime :scheduled_at
      t.references :author, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :website_articles, :public_id, unique: true
    add_index :website_articles, [ :article_type, :slug ], unique: true

    create_table :website_nav_items do |t|
      t.string :label, null: false
      t.string :url
      t.references :website_page, foreign_key: true
      t.integer :position, null: false, default: 0
      t.string :location, null: false, default: "header"
      t.boolean :visible, null: false, default: true
      t.timestamps
    end
  end
end
