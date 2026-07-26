# frozen_string_literal: true

class AddRateLimitCounterLifecycle < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :rate_limit_counters, :expires_at, :datetime

    add_index :rate_limit_counters,
      :expires_at,
      algorithm: :concurrently,
      name: "index_rate_limit_counters_on_expires_at"
    add_index :rate_limit_counters,
      :window_start,
      algorithm: :concurrently,
      name: "index_rate_limit_counters_on_window_start"
    add_index :rate_limit_counters,
      :key,
      opclass: :varchar_pattern_ops,
      algorithm: :concurrently,
      name: "index_rate_limit_counters_on_key_pattern"
  end

  def down
    remove_index :rate_limit_counters,
      name: "index_rate_limit_counters_on_key_pattern",
      algorithm: :concurrently
    remove_index :rate_limit_counters,
      name: "index_rate_limit_counters_on_window_start",
      algorithm: :concurrently
    remove_index :rate_limit_counters,
      name: "index_rate_limit_counters_on_expires_at",
      algorithm: :concurrently
    remove_column :rate_limit_counters, :expires_at
  end
end
