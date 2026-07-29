# frozen_string_literal: true

require_relative "lifecycle_error"
require_relative "manifest"

module Mcweb
  module Plugins
    class OwnedDataPurger
      MODEL_SCOPES = {
        "plugin_outbound_deliveries" => ->(plugin_id) {
          PluginOutboundDelivery.where(owner_plugin_id: plugin_id)
        },
        "plugin_job_runs" => ->(plugin_id) {
          PluginJobRun.where(owner_plugin_id: plugin_id)
        },
        "plugin_setting_versions" => ->(plugin_id) {
          PluginSettingVersion.where(plugin_id:)
        }
      }.freeze

      def self.call(plugin_id:)
        new(plugin_id:).call
      end

      def initialize(plugin_id:)
        @plugin_id = plugin_id.to_s
        unless @plugin_id.match?(Manifest::ID_PATTERN)
          raise ArgumentError, "invalid plugin id"
        end
      end

      def call
        raise LifecycleError, "plugin data storage is unavailable" unless defined?(ActiveRecord::Base)

        counts = {}
        ActiveRecord::Base.transaction(requires_new: true) do
          purge_storage_objects(counts)
          MODEL_SCOPES.each do |table, scope|
            next unless ActiveRecord::Base.connection.data_source_exists?(table)

            counts[table] = scope.call(@plugin_id).delete_all
          end
        end
        counts.freeze
      end

      private

      def purge_storage_objects(counts)
        table = "plugin_storage_objects"
        return unless ActiveRecord::Base.connection.data_source_exists?(table)

        relation = PluginStorageObject.where(owner_plugin_id: @plugin_id)
        counts[table] = relation.count
        relation.find_each(&:destroy!)
      end
    end
  end
end
