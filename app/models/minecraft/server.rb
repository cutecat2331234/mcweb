module Minecraft
  class Server < ApplicationRecord
    include HasPublicId

    has_encrypted :connector_secret, encrypted_attribute: :encrypted_connector_secret

    belongs_to :node, class_name: "Minecraft::Node", foreign_key: :minecraft_node_id, optional: true
    has_many :identities, class_name: "Minecraft::Identity", foreign_key: :minecraft_server_id, dependent: :destroy
    has_many :link_codes, class_name: "Minecraft::LinkCode", foreign_key: :minecraft_server_id, dependent: :destroy
    has_many :connector_tasks, class_name: "Minecraft::ConnectorTask", foreign_key: :minecraft_server_id, dependent: :destroy
    has_many :node_tasks, class_name: "Minecraft::NodeTask", foreign_key: :minecraft_server_id, dependent: :destroy
    has_many :processed_deliveries, class_name: "Minecraft::ProcessedDelivery", foreign_key: :minecraft_server_id, dependent: :destroy
    has_many :server_snapshots, class_name: "Minecraft::ServerSnapshot", foreign_key: :minecraft_server_id, dependent: :destroy
    has_many :player_sessions, class_name: "Minecraft::PlayerSession", foreign_key: :minecraft_server_id, dependent: :destroy
    has_many :world_backups,
      class_name: "Minecraft::WorldBackup",
      foreign_key: :minecraft_server_id,
      inverse_of: :server,
      dependent: :restrict_with_error
    has_many :world_restore_plans,
      class_name: "Minecraft::WorldRestorePlan",
      foreign_key: :minecraft_server_id,
      inverse_of: :server,
      dependent: :restrict_with_error

    enum :status, { offline: "offline", online: "online", maintenance: "maintenance" }, validate: true
    enum :connection_mode, { direct: "direct", node: "node" }, validate: true, prefix: true
    enum :process_state, {
      stopped: "stopped",
      starting: "starting",
      running: "running",
      stopping: "stopping",
      error: "error"
    }, validate: true, prefix: true

    PROCESS_DRIVERS = %w[systemd docker script nssm].freeze

    validates :name, presence: true
    validates :port, numericality: { only_integer: true, in: 1..65535 }
    validates :process_driver, inclusion: { in: PROCESS_DRIVERS }, allow_blank: true
    validate :restore_target_configuration_is_stable, on: :update

    scope :online_servers, -> { where(status: :online) }
    scope :managed_by_node, -> { where.not(minecraft_node_id: nil) }
    scope :process_running, -> { where(process_state: :running) }

    # Alias matches scope name and call sites expecting process_running?
    alias_method :process_running?, :process_state_running?

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

    def node_managed?
      minecraft_node_id.present?
    end

    def recent_node_tasks(limit = 20)
      node_tasks.order(created_at: :desc).limit(limit)
    end

    def last_host_metrics
      metadata.dig("last_metrics", "host") || metadata["last_metrics"]
    end

    def effective_proxy_listen_url
      proxy_listen_url.presence || node&.effective_proxy_listen_url
    end

    def plugin_website_url(rails_base_url)
      connection_mode_node? ? effective_proxy_listen_url.to_s : rails_base_url.to_s
    end

    def active_world_restore_plan
      world_restore_plans.active.order(created_at: :desc).first
    end

    def world_restore_blocks_start?
      world_restore_plans.blocking_server_start.exists? ||
        ActiveModel::Type::Boolean.new.cast(node&.metadata.to_h["world_restore_recovery_required"])
    end

    private

    def restore_target_configuration_is_stable
      return unless world_restore_plans.active.exists?

      metadata_changed = will_save_change_to_metadata? &&
        metadata_in_database.to_h["world_directory"].to_s != metadata.to_h["world_directory"].to_s
      target_changed = will_save_change_to_minecraft_node_id? ||
        will_save_change_to_working_directory? ||
        will_save_change_to_process_driver? ||
        will_save_change_to_process_config? ||
        metadata_changed
      errors.add(:base, :world_restore_active) if target_changed
    end
  end
end
