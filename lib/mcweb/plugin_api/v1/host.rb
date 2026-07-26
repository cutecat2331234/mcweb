# frozen_string_literal: true

require_relative "commerce"
require_relative "forum"
require_relative "events"
require_relative "identity"
require_relative "jobs"
require_relative "site"
require_relative "settings"

module Mcweb
  module PluginApi
    module V1
      class Host
        API_VERSION = "1"

        attr_reader :plugin_id, :api_version, :capabilities, :commerce, :forum, :events,
                    :identity, :jobs, :site, :settings

        def initialize(
          manifest:,
          event_bus:,
          capability_auditor: nil,
          permission_catalog: nil
        )
          @plugin_id = manifest.id
          @api_version = API_VERSION
          @capabilities = manifest.capabilities
          @commerce = Commerce.new(capability_auditor:)
          @forum = Forum.new(capability_auditor:)
          @events = Events.new(event_bus:, capability_auditor:)
          @identity = Identity.new(
            plugin_id: manifest.id,
            permission_catalog:,
            capability_auditor:
          )
          @jobs = Jobs.new(manifest:, capability_auditor:)
          @site = Site.new(capability_auditor:)
          @settings = Settings.new(manifest:, capability_auditor:)
          freeze
        end

        def declares_capability?(capability)
          capabilities.include?(capability.to_s)
        end

        def to_h
          {
            plugin_id: plugin_id,
            api_version: api_version,
            capabilities: capabilities
          }.freeze
        end
      end
    end
  end
end
