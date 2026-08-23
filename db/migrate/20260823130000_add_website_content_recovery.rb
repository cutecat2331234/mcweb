# frozen_string_literal: true

class AddWebsiteContentRecovery < ActiveRecord::Migration[8.1]
  CONTENT_TABLES = %i[website_pages website_articles].freeze
  REVISION_TABLES = %i[website_page_revisions website_article_revisions].freeze
  REVISION_EVENTS = %w[
    update block_create block_update block_delete block_reorder publish schedule archive discard restore
    revision_restore purge legacy
  ].freeze
  PRIVILEGED_ROLE_KEYS = %w[owner super_admin].freeze
  RECOVERY_ROLE_KEYS = %w[owner super_admin editor].freeze
  PERMISSIONS = [
    {
      key: "website.content.restore",
      name: "Restore discarded website content",
      category: "website",
      description: "Review the website recycle bin and restore eligible pages and articles as drafts"
    },
    {
      key: "website.content.purge",
      name: "Permanently purge website content",
      category: "website",
      description: "Permanently remove mutable website content after retention and safety checks"
    }
  ].freeze

  def up
    add_content_lifecycle_columns(:website_pages, add_lock_version: false)
    add_content_lifecycle_columns(:website_articles, add_lock_version: true)
    strengthen_page_revisions
    create_article_revisions
    replace_slug_indexes
    add_lifecycle_constraints
    add_revision_constraints
    install_immutability_triggers
    install_permissions
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "website recovery history and permission grants are immutable production evidence"
  end

  private

  def add_content_lifecycle_columns(table, add_lock_version:)
    add_column table, :lock_version, :integer, null: false, default: 0 if add_lock_version
    add_column table, :discarded_at, :datetime
    add_reference table, :discarded_by, foreign_key: { to_table: :users }
    add_column table, :discard_reason, :text
    add_column table, :purge_at, :datetime
    add_column table, :discard_idempotency_key_digest, :string, limit: 64
    add_column table, :restore_idempotency_key_digest, :string, limit: 64
    add_column table, :purged_at, :datetime
    add_reference table, :purged_by, foreign_key: { to_table: :users }
    add_column table, :purge_reason, :text
    add_column table, :purge_idempotency_key_digest, :string, limit: 64

    add_index table, %i[discarded_at purge_at], name: "idx_#{table}_recycle_bin"
    add_index table, :discard_idempotency_key_digest,
      unique: true,
      where: "discard_idempotency_key_digest IS NOT NULL",
      name: "idx_#{table}_discard_request"
    add_index table, :restore_idempotency_key_digest,
      unique: true,
      where: "restore_idempotency_key_digest IS NOT NULL",
      name: "idx_#{table}_restore_request"
    add_index table, :purge_idempotency_key_digest,
      unique: true,
      where: "purge_idempotency_key_digest IS NOT NULL",
      name: "idx_#{table}_purge_request"
  end

  def strengthen_page_revisions
    add_column :website_page_revisions, :event_type, :string, null: false, default: "legacy"
    add_column :website_page_revisions, :reason, :text
    add_column :website_page_revisions, :request_id_digest, :string, limit: 64
    add_column :website_page_revisions, :operation_digest, :string, limit: 64
    add_column :website_page_revisions, :source_lock_version, :integer, null: false, default: 0
    add_index :website_page_revisions, %i[website_page_id request_id_digest],
      unique: true,
      where: "request_id_digest IS NOT NULL",
      name: "idx_website_page_revisions_request"
  end

  def create_article_revisions
    create_table :website_article_revisions do |t|
      t.references :website_article, null: false, foreign_key: true
      t.references :author, foreign_key: { to_table: :users }
      t.jsonb :snapshot, null: false
      t.integer :revision_number, null: false
      t.string :event_type, null: false
      t.text :reason
      t.string :request_id_digest, limit: 64
      t.string :operation_digest, limit: 64
      t.integer :source_lock_version, null: false, default: 0
      t.datetime :created_at, null: false
    end

    add_index :website_article_revisions, %i[website_article_id revision_number],
      unique: true,
      name: "idx_website_article_revisions_number"
    add_index :website_article_revisions, %i[website_article_id request_id_digest],
      unique: true,
      where: "request_id_digest IS NOT NULL",
      name: "idx_website_article_revisions_request"
  end

  def replace_slug_indexes
    remove_index :website_pages, :slug, if_exists: true
    add_index :website_pages, :slug,
      unique: true,
      where: "discarded_at IS NULL AND purged_at IS NULL",
      name: "idx_website_pages_active_slug"

    remove_index :website_articles, :slug, if_exists: true
    add_index :website_articles, :slug,
      unique: true,
      where: "discarded_at IS NULL AND purged_at IS NULL",
      name: "idx_website_articles_active_slug"
  end

  def add_lifecycle_constraints
    CONTENT_TABLES.each do |table|
      add_check_constraint table, <<~SQL.squish, name: "chk_#{table}_discard_shape"
        (
          discarded_at IS NULL AND discarded_by_id IS NULL AND discard_reason IS NULL AND
          purge_at IS NULL AND discard_idempotency_key_digest IS NULL
        ) OR (
          discarded_at IS NOT NULL AND discard_reason IS NOT NULL AND
          char_length(discard_reason) BETWEEN 1 AND 1000 AND purge_at IS NOT NULL AND
          purge_at >= discarded_at AND discard_idempotency_key_digest ~ '^[0-9a-f]{64}$'
        )
      SQL
      add_check_constraint table, <<~SQL.squish, name: "chk_#{table}_purge_shape"
        (
          purged_at IS NULL AND purged_by_id IS NULL AND purge_reason IS NULL AND
          purge_idempotency_key_digest IS NULL
        ) OR (
          purged_at IS NOT NULL AND purge_reason IS NOT NULL AND
          char_length(purge_reason) BETWEEN 1 AND 1000 AND
          purge_idempotency_key_digest ~ '^[0-9a-f]{64}$' AND
          discarded_at IS NOT NULL AND purge_at IS NOT NULL AND purged_at >= purge_at
        )
      SQL
      add_check_constraint table,
        "restore_idempotency_key_digest IS NULL OR restore_idempotency_key_digest ~ '^[0-9a-f]{64}$'",
        name: "chk_#{table}_restore_request"
    end

    add_check_constraint :website_pages, <<~SQL.squish, name: "chk_website_pages_purged_tombstone"
      purged_at IS NULL OR (
        status = 'archived' AND website_theme_id IS NULL AND author_id IS NULL AND
        title = public_id AND
        published_at IS NULL AND scheduled_at IS NULL AND seo = '{}'::jsonb AND
        translations = '{}'::jsonb
      )
    SQL
    add_check_constraint :website_articles, <<~SQL.squish, name: "chk_website_articles_purged_tombstone"
      purged_at IS NULL OR (
        status = 'archived' AND author_id IS NULL AND published_at IS NULL AND
        title = public_id AND
        scheduled_at IS NULL AND summary IS NULL AND body IS NULL AND
        seo = '{}'::jsonb AND translations = '{}'::jsonb
      )
    SQL
  end

  def install_immutability_triggers
    execute <<~SQL
      CREATE OR REPLACE FUNCTION prevent_website_revision_mutation()
      RETURNS trigger AS $$
      BEGIN
        RAISE EXCEPTION 'website content revisions are immutable';
      END;
      $$ LANGUAGE plpgsql;
    SQL

    REVISION_TABLES.each do |table|
      execute <<~SQL
        CREATE TRIGGER #{table}_immutable
        BEFORE UPDATE OR DELETE ON #{table}
        FOR EACH ROW EXECUTE FUNCTION prevent_website_revision_mutation();
      SQL
    end

    execute <<~SQL
      CREATE OR REPLACE FUNCTION protect_website_content_lifecycle()
      RETURNS trigger AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'website content must use the recoverable lifecycle';
        END IF;
        IF OLD.purged_at IS NOT NULL THEN
          RAISE EXCEPTION 'purged website tombstones are immutable';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    SQL

    CONTENT_TABLES.each do |table|
      execute <<~SQL
        CREATE TRIGGER #{table}_lifecycle_guard
        BEFORE UPDATE OR DELETE ON #{table}
        FOR EACH ROW EXECUTE FUNCTION protect_website_content_lifecycle();
      SQL
    end
  end

  def add_revision_constraints
    REVISION_TABLES.each do |table|
      add_check_constraint table,
        "event_type IN (#{quoted_list(REVISION_EVENTS)})",
        name: "chk_#{table}_event_type"
      add_check_constraint table,
        "reason IS NULL OR char_length(reason) BETWEEN 1 AND 1000",
        name: "chk_#{table}_reason"
      add_check_constraint table,
        <<~SQL.squish,
          (
            request_id_digest IS NULL AND operation_digest IS NULL
          ) OR (
            request_id_digest ~ '^[0-9a-f]{64}$' AND
            operation_digest ~ '^[0-9a-f]{64}$'
          )
        SQL
        name: "chk_#{table}_request"
      add_check_constraint table,
        "source_lock_version >= 0",
        name: "chk_#{table}_source_version"
    end
  end

  def install_permissions
    PERMISSIONS.each do |attributes|
      execute <<~SQL.squish
        INSERT INTO permissions (key, name, category, description, created_at, updated_at)
        VALUES (
          #{quote(attributes.fetch(:key))}, #{quote(attributes.fetch(:name))},
          #{quote(attributes.fetch(:category))}, #{quote(attributes.fetch(:description))},
          CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        )
        ON CONFLICT (key) DO UPDATE SET
          name = EXCLUDED.name,
          category = EXCLUDED.category,
          description = EXCLUDED.description,
          updated_at = CURRENT_TIMESTAMP
      SQL
    end

    grant_roles(RECOVERY_ROLE_KEYS, %w[website.content.restore])
    grant_roles(PRIVILEGED_ROLE_KEYS, %w[website.content.purge])
    grant_legacy_editors_recovery
    grant_legacy_editor_groups_recovery
  end

  def grant_roles(role_keys, permission_keys)
    execute <<~SQL.squish
      INSERT INTO role_permissions (role_id, permission_id, created_at, updated_at)
      SELECT roles.id, permissions.id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM roles CROSS JOIN permissions
      WHERE roles.key IN (#{quoted_list(role_keys)})
        AND permissions.key IN (#{quoted_list(permission_keys)})
      ON CONFLICT (role_id, permission_id) DO NOTHING
    SQL
  end

  def grant_legacy_editors_recovery
    execute <<~SQL.squish
      INSERT INTO role_permissions (role_id, permission_id, created_at, updated_at)
      SELECT DISTINCT legacy_grants.role_id, recovery_permission.id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM role_permissions AS legacy_grants
      INNER JOIN permissions AS legacy_permission ON legacy_permission.id = legacy_grants.permission_id
      CROSS JOIN permissions AS recovery_permission
      WHERE legacy_permission.key IN ('website.pages.edit', 'website.articles.edit')
        AND recovery_permission.key = 'website.content.restore'
      ON CONFLICT (role_id, permission_id) DO NOTHING
    SQL
  end

  def grant_legacy_editor_groups_recovery
    execute <<~SQL.squish
      UPDATE community_user_groups
      SET permissions = permissions || '["website.content.restore"]'::jsonb
      WHERE (
        permissions @> '["website.pages.edit"]'::jsonb OR
        permissions @> '["website.articles.edit"]'::jsonb
      ) AND NOT permissions @> '["website.content.restore"]'::jsonb
    SQL
  end

  def quoted_list(values)
    values.map { |value| quote(value) }.join(", ")
  end

  def quote(value)
    connection.quote(value)
  end
end
