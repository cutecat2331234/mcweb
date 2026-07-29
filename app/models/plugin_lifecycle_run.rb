# frozen_string_literal: true

class PluginLifecycleRun < ApplicationRecord
  STATES = %w[running succeeded failed interrupted recovered].freeze
  ACTIONS = %w[install upgrade enable disable uninstall rollback recover].freeze

  belongs_to :plugin_installation, optional: true, inverse_of: :lifecycle_runs
  belongs_to :actor, class_name: "User", optional: true
  has_many :steps,
           -> { order(:sequence) },
           class_name: "PluginLifecycleStep",
           dependent: :delete_all,
           inverse_of: :plugin_lifecycle_run

  validates :operation_id, presence: true, length: { maximum: 191 },
                           uniqueness: true
  validates :action, inclusion: { in: ACTIONS }
  validates :state, inclusion: { in: STATES }
  validates :started_at, presence: true

  scope :running, -> { where(state: "running") }
  scope :recent_first, -> { order(started_at: :desc, id: :desc) }
end
