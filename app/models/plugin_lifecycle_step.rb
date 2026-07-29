# frozen_string_literal: true

class PluginLifecycleStep < ApplicationRecord
  STATES = %w[succeeded failed skipped].freeze

  belongs_to :plugin_lifecycle_run, inverse_of: :steps

  validates :sequence, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 0
  }, uniqueness: { scope: :plugin_lifecycle_run_id }
  validates :step_key, presence: true, length: { maximum: 191 }
  validates :idempotency_key, presence: true, length: { maximum: 191 },
                              uniqueness: { scope: :plugin_lifecycle_run_id }
  validates :state, inclusion: { in: STATES }
  validates :started_at, presence: true
end
