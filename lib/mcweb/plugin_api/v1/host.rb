# frozen_string_literal: true

require_relative "forum"
require_relative "events"
require_relative "site"

module Mcweb
  module PluginApi
    module V1
      class Host
        API_VERSION = "1"

        attr_reader :plugin_id, :api_version, :capabilities, :forum, :events, :site

        def initialize(manifest:, event_bus:, capability_auditor: nil)
          @plugin_id = manifest.id
          @api_version = API_VERSION
          @capabilities = manifest.capabilities
          @forum = Forum.new(capability_auditor:)
          @events = Events.new(event_bus:, capability_auditor:)
          @site = Site.new(capability_auditor:)
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
