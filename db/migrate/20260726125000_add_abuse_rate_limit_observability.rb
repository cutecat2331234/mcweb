# frozen_string_literal: true

class AddAbuseRateLimitObservability < ActiveRecord::Migration[8.1]
  def change
    add_column :rate_limit_counters, :blocked_count, :bigint, null: false, default: 0
    add_column :rate_limit_counters, :last_blocked_at, :datetime
    add_index :rate_limit_counters, :last_blocked_at
    add_check_constraint :rate_limit_counters,
      "blocked_count >= 0",
      name: "rate_limit_counters_blocked_count_nonnegative"
  end
end
