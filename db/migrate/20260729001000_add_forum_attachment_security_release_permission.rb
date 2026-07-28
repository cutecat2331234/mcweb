# frozen_string_literal: true

class AddForumAttachmentSecurityReleasePermission < ActiveRecord::Migration[8.1]
  PERMISSION_KEY = "forum.attachments.security.release"
  PRIVILEGED_ROLE_KEYS = %w[owner super_admin forum_admin].freeze

  def up
    execute <<~SQL.squish
      INSERT INTO permissions (key, name, category, description, created_at, updated_at)
      VALUES (
        #{connection.quote(PERMISSION_KEY)},
        'Release quarantined attachments',
        'forum',
        'Approve a quarantined attachment as a reviewed false positive',
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      )
      ON CONFLICT (key) DO NOTHING
    SQL

    execute <<~SQL.squish
      INSERT INTO role_permissions (role_id, permission_id, created_at, updated_at)
      SELECT roles.id, permissions.id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM roles
      CROSS JOIN permissions
      WHERE roles.key IN (#{quoted_role_keys})
        AND permissions.key = #{connection.quote(PERMISSION_KEY)}
      ON CONFLICT (role_id, permission_id) DO NOTHING
    SQL
  end

  def down
    execute <<~SQL.squish
      DELETE FROM role_permissions
      WHERE permission_id IN (
        SELECT id FROM permissions WHERE key = #{connection.quote(PERMISSION_KEY)}
      )
    SQL
    execute <<~SQL.squish
      DELETE FROM permissions
      WHERE key = #{connection.quote(PERMISSION_KEY)}
    SQL
  end

  private

  def quoted_role_keys
    PRIVILEGED_ROLE_KEYS.map { |key| connection.quote(key) }.join(", ")
  end
end
