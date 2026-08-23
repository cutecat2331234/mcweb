# frozen_string_literal: true

class AddWebsiteThemeVersionGovernance < ActiveRecord::Migration[8.1]
  REVISION_EVENTS = %w[create update activate deactivate restore legacy].freeze

  def up
    add_column :website_themes, :lock_version, :integer, null: false, default: 0

    create_table :website_theme_revisions do |t|
      # A Theme with immutable history cannot be hard-deleted. Keeping the
      # parent foreign key makes every revision reachable from its Theme.
      t.references :website_theme, null: false, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      t.jsonb :snapshot, null: false
      t.integer :revision_number, null: false
      t.string :event_type, null: false
      t.text :reason
      t.integer :source_lock_version, null: false
      t.references :source_revision,
        foreign_key: { to_table: :website_theme_revisions }
      t.string :request_id_digest, limit: 64
      t.string :operation_digest, limit: 64
      t.datetime :created_at, null: false
    end

    add_index :website_theme_revisions,
      %i[website_theme_id revision_number],
      unique: true,
      name: "idx_website_theme_revisions_number"
    add_index :website_theme_revisions,
      :request_id_digest,
      unique: true,
      where: "request_id_digest IS NOT NULL",
      name: "idx_website_theme_revisions_request"
    add_index :website_theme_revisions,
      %i[website_theme_id created_at id],
      name: "idx_website_theme_revisions_history"

    add_check_constraint :website_theme_revisions,
      "revision_number >= 1",
      name: "chk_website_theme_revisions_number"
    add_check_constraint :website_theme_revisions,
      "source_lock_version >= 0",
      name: "chk_website_theme_revisions_source_version"
    add_check_constraint :website_theme_revisions,
      "event_type IN (#{quoted_list(REVISION_EVENTS)})",
      name: "chk_website_theme_revisions_event"
    add_check_constraint :website_theme_revisions, <<~SQL.squish,
      jsonb_typeof(snapshot) = 'object' AND
      snapshot ?& ARRAY['name', 'key', 'tokens', 'active'] AND
      snapshot - ARRAY['name', 'key', 'tokens', 'active'] = '{}'::jsonb AND
      jsonb_typeof(snapshot->'name') = 'string' AND
      jsonb_typeof(snapshot->'key') = 'string' AND
      jsonb_typeof(snapshot->'tokens') = 'object' AND
      jsonb_typeof(snapshot->'active') = 'boolean'
    SQL
      name: "chk_website_theme_revisions_snapshot"
    add_check_constraint :website_theme_revisions, <<~SQL.squish,
      (
        event_type = 'restore' AND
        source_revision_id IS NOT NULL AND
        reason IS NOT NULL AND char_length(reason) BETWEEN 1 AND 1000 AND
        request_id_digest ~ '^[0-9a-f]{64}$' AND
        operation_digest ~ '^[0-9a-f]{64}$'
      ) OR (
        event_type <> 'restore' AND
        source_revision_id IS NULL AND
        request_id_digest IS NULL AND
        operation_digest IS NULL AND
        (reason IS NULL OR char_length(reason) BETWEEN 1 AND 1000)
      )
    SQL
      name: "chk_website_theme_revisions_operation"

    backfill_legacy_revisions
    normalize_active_themes
    add_index :website_themes,
      :active,
      unique: true,
      where: "active = TRUE",
      name: "idx_website_themes_one_active"
    install_immutability_trigger
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "website Theme revision history is immutable production evidence"
  end

  private

  def backfill_legacy_revisions
    execute <<~SQL.squish
      INSERT INTO website_theme_revisions (
        website_theme_id, snapshot, revision_number, event_type,
        source_lock_version, created_at
      )
      SELECT
        id,
        jsonb_build_object(
          'name', name,
          'key', key,
          'tokens', COALESCE(tokens, '{}'::jsonb),
          'active', active
        ),
        1,
        'legacy',
        lock_version,
        COALESCE(updated_at, created_at, CURRENT_TIMESTAMP)
      FROM website_themes
    SQL
  end

  def install_immutability_trigger
    execute <<~SQL
      CREATE OR REPLACE FUNCTION prevent_website_theme_revision_mutation()
      RETURNS trigger AS $$
      BEGIN
        RAISE EXCEPTION 'website Theme revisions are immutable';
      END;
      $$ LANGUAGE plpgsql;
    SQL

    execute <<~SQL
      CREATE TRIGGER website_theme_revisions_immutable
      BEFORE UPDATE OR DELETE ON website_theme_revisions
      FOR EACH ROW EXECUTE FUNCTION prevent_website_theme_revision_mutation();
    SQL
  end

  def normalize_active_themes
    execute <<~SQL.squish
      WITH deactivated AS (
        UPDATE website_themes
        SET
          active = FALSE,
          lock_version = lock_version + 1,
          updated_at = CURRENT_TIMESTAMP
        WHERE active = TRUE
          AND id <> (SELECT MIN(id) FROM website_themes WHERE active = TRUE)
        RETURNING id, name, key, tokens, lock_version
      )
      INSERT INTO website_theme_revisions (
        website_theme_id, snapshot, revision_number, event_type,
        source_lock_version, created_at
      )
      SELECT
        id,
        jsonb_build_object(
          'name', name,
          'key', key,
          'tokens', COALESCE(tokens, '{}'::jsonb),
          'active', FALSE
        ),
        2,
        'deactivate',
        lock_version - 1,
        CURRENT_TIMESTAMP
      FROM deactivated
    SQL
  end

  def quoted_list(values)
    values.map { |value| connection.quote(value) }.join(", ")
  end
end
