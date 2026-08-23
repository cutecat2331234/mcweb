module Minecraft
  class ConnectorTask < ApplicationRecord
    belongs_to :server, class_name: "Minecraft::Server", foreign_key: :minecraft_server_id
    belongs_to :fulfillment, class_name: "Commerce::Fulfillment", foreign_key: :store_fulfillment_id, optional: true

    enum :status, { pending: "pending", claimed: "claimed", completed: "completed", failed: "failed" }, validate: true

    validates :task_type, presence: true

    scope :claimable, -> { where(status: :pending).order(:created_at) }

    after_commit :simulate_in_developer_mode, on: %i[create update]
    after_commit :reconcile_player_access_rule, on: :update

    def claim!
      update!(status: :claimed, claimed_at: Time.current)
    end

    def complete!(result_data = {})
      update!(status: :completed, result: result_data, completed_at: Time.current)
    end

    def fail!(result_data = {})
      update!(status: :failed, result: result_data, completed_at: Time.current)
    end

    private

    def simulate_in_developer_mode
      return unless pending?
      return unless previous_changes.key?("id") || previous_changes.key?("status")
      return unless Mcweb::DeveloperMode.enabled?
      return unless Mcweb::DeveloperMode.integration(:minecraft_nodes) == :simulate

      result = Minecraft::TaskDispatcher.call(
        server: server,
        task: self,
        result: {
          success: true,
          status: "completed",
          simulated: true,
          developer_mode: true
        },
        action: :complete
      )
      return if result.success?

      Rails.logger.error(
        "[Minecraft::ConnectorTask] Developer Mode simulation failed " \
        "task_id=#{id} error=#{result.error}"
      )
    rescue StandardError => error
      Rails.logger.error(
        "[Minecraft::ConnectorTask] Developer Mode simulation failed " \
        "task_id=#{id} error=#{error.class}"
      )
    end

    def reconcile_player_access_rule
      return unless previous_changes.key?("status")
      return unless completed? || failed?
      return unless defined?(Minecraft::PlayerAccessRule)

      result = Minecraft::ReconcilePlayerAccessRule.call(task: self)
      return if result.success?

      Rails.logger.error(
        "[Minecraft::ConnectorTask] player access rule reconciliation failed " \
        "task_id=#{id} code=#{result.code}"
      )
    rescue StandardError => error
      Rails.logger.error(
        "[Minecraft::ConnectorTask] player access rule reconciliation failed " \
        "task_id=#{id} error=#{error.class}"
      )
    end
  end
end
