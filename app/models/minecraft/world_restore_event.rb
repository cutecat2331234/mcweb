# frozen_string_literal: true

module Minecraft
  class WorldRestoreEvent < ApplicationRecord
    self.table_name = "minecraft_world_restore_events"

    PHASES = %w[
      planned authorized queued running accepted process_stopped pre_snapshot_started
      pre_snapshot_durable archive_validated staging_started staging_verified live_preserved
      replacement_installed post_install_verified rollback_started rolled_back completed failed
      recovery_required expired cancelled
    ].freeze

    belongs_to :restore_plan,
      class_name: "Minecraft::WorldRestorePlan",
      foreign_key: :minecraft_world_restore_plan_id,
      inverse_of: :events
    belongs_to :actor, class_name: "User", optional: true

    validates :sequence, numericality: { only_integer: true, greater_than: 0 },
      uniqueness: { scope: :minecraft_world_restore_plan_id }
    validates :event_type, :phase, :payload_digest, presence: true
    validates :event_type, format: { with: /\Aminecraft\.world_restore\.[a-z0-9_]+\z/ }
    validates :phase, inclusion: { in: PHASES }
    validates :payload_digest, format: { with: /\A[0-9a-f]{64}\z/ }

    before_update { throw(:abort) }
    before_destroy { throw(:abort) }
  end
end
