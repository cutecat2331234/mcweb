# frozen_string_literal: true

class PluginProcessAck < ApplicationRecord
  STATUSES = %w[healthy failed].freeze
  PROCESS_KINDS = %w[web worker console other].freeze

  belongs_to :plugin_generation, inverse_of: :process_acks

  validates :process_uid, presence: true, length: { maximum: 191 },
                          uniqueness: { scope: :plugin_generation_id }
  validates :process_kind, inclusion: { in: PROCESS_KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :acked_at, :last_seen_at, presence: true
end
