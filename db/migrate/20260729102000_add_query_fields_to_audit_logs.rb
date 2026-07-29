# frozen_string_literal: true

class AddQueryFieldsToAuditLogs < ActiveRecord::Migration[8.0]
  def up
    add_column :audit_logs, :request_id, :string, limit: 100

    execute <<~SQL.squish
      UPDATE audit_logs
      SET request_id = LEFT(COALESCE(metadata->>'request_id', metadata->>'requestId'), 100)
      WHERE request_id IS NULL
        AND COALESCE(metadata->>'request_id', metadata->>'requestId') IS NOT NULL
    SQL

    add_index :audit_logs, :request_id
    add_index :audit_logs, :resource_public_id
    add_index :audit_logs, %i[actor_id created_at]
    add_index :audit_logs, %i[action created_at]
  end

  def down
    remove_index :audit_logs, %i[action created_at]
    remove_index :audit_logs, %i[actor_id created_at]
    remove_index :audit_logs, :resource_public_id
    remove_index :audit_logs, :request_id
    remove_column :audit_logs, :request_id
  end
end
