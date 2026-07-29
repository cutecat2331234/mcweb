# frozen_string_literal: true

class PluginInstallation < ApplicationRecord
  STATES = %w[
    uploaded validated staged installing installed enabling enabled
    disabling disabled upgrading uninstalling uninstalled failed
    quarantined rolling_back
  ].freeze
  DESIRED_STATES = %w[enabled disabled uninstalled].freeze
  EDITIONS = %w[ce ee].freeze
  BUSY_STATES = %w[
    staged installing enabling disabling upgrading uninstalling rolling_back
  ].freeze

  has_many :lifecycle_runs,
           class_name: "PluginLifecycleRun",
           dependent: :restrict_with_error,
           inverse_of: :plugin_installation
  has_many :releases,
           class_name: "PluginRelease",
           dependent: :delete_all,
           inverse_of: :plugin_installation

  validates :plugin_id, presence: true, length: { maximum: 191 },
                        uniqueness: true
  validates :current_state, inclusion: { in: STATES }
  validates :desired_state, inclusion: { in: DESIRED_STATES }
  validates :edition, inclusion: { in: EDITIONS }
end
