# frozen_string_literal: true

module Minecraft
  class Node < ApplicationRecord
    include HasPublicId

    has_encrypted :node_secret, encrypted_attribute: :encrypted_node_secret

    has_many :servers, class_name: "Minecraft::Server", foreign_key: :minecraft_node_id, dependent: :nullify
    has_many :node_tasks, class_name: "Minecraft::NodeTask", foreign_key: :minecraft_node_id, dependent: :destroy
    has_many :operation_batches,
      class_name: "Minecraft::NodeOperationBatch",
      foreign_key: :minecraft_node_id,
      inverse_of: :node,
      dependent: :restrict_with_error
    has_many :metric_snapshots, class_name: "Minecraft::NodeMetricSnapshot", foreign_key: :minecraft_node_id, dependent: :destroy

    enum :status, { offline: "offline", online: "online", maintenance: "maintenance" }, validate: true

    validates :name, presence: true

    def wake_for_tasks!
      update!(tasks_wake_at: Time.current)
    end

    def heartbeat!
      update!(last_heartbeat_at: Time.current, status: :online)
    end

    def generate_node_secret!
      secret = SecureRandom.hex(32)
      self.node_secret = secret
      self.node_secret_fingerprint = Digest::SHA256.hexdigest(secret)[0, 16]
      save!
      secret
    end

    def verify_node_secret(secret)
      node_secret.present? && node_secret == secret
    end

    def effective_proxy_listen_url
      proxy_listen_url.presence || "http://127.0.0.1:9876"
    end

    def supports_operation_batches?
      Array(metadata["node_protocol_versions"]).map(&:to_i).include?(2)
    end

    def supports_node_operation?(operation_type)
      supports_operation_batches? &&
        Array(metadata["operation_types"]).map(&:to_s).include?(operation_type.to_s)
    end
  end
end
