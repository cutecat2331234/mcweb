module Minecraft
  class Server < ApplicationRecord
    include HasPublicId

    has_encrypted :connector_secret, encrypted_attribute: :encrypted_connector_secret

    has_many :identities, class_name: "Minecraft::Identity", foreign_key: :minecraft_server_id, dependent: :destroy
    has_many :link_codes, class_name: "Minecraft::LinkCode", foreign_key: :minecraft_server_id, dependent: :destroy
    has_many :connector_tasks, class_name: "Minecraft::ConnectorTask", foreign_key: :minecraft_server_id, dependent: :destroy
    has_many :processed_deliveries, class_name: "Minecraft::ProcessedDelivery", foreign_key: :minecraft_server_id, dependent: :destroy
    has_many :server_snapshots, class_name: "Minecraft::ServerSnapshot", foreign_key: :minecraft_server_id, dependent: :destroy

    enum :status, { offline: "offline", online: "online", maintenance: "maintenance" }, validate: true

    validates :name, presence: true
    validates :port, numericality: { only_integer: true, in: 1..65535 }

    scope :online_servers, -> { where(status: :online) }

    def heartbeat!
      update!(last_heartbeat_at: Time.current, status: :online)
    end

    def generate_connector_secret!
      secret = SecureRandom.hex(32)
      self.connector_secret = secret
      self.connector_secret_fingerprint = Digest::SHA256.hexdigest(secret)[0, 16]
      save!
      secret
    end

    def verify_connector_secret(secret)
      connector_secret.present? && connector_secret == secret
    end
  end
end
