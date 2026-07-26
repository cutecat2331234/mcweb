# frozen_string_literal: true

require "test_helper"

module Minecraft
  class DeveloperModeIntegrationsTest < ActiveSupport::TestCase
    setup do
      @node = Minecraft::Node.create!(
        public_id: "node_dev_#{SecureRandom.hex(4)}",
        name: "Developer node",
        status: :online,
        last_heartbeat_at: Time.current
      )
      @server = Minecraft::Server.create!(
        public_id: "server_dev_#{SecureRandom.hex(4)}",
        name: "Developer server",
        node: @node,
        status: :online,
        connection_mode: :node,
        process_state: :stopped,
        port: 25_565
      )
    end

    test "node simulation completes a task without waiting for a real node" do
      with_developer_mode do
        result = Minecraft::EnqueueNodeTask.call(
          node: @node,
          server: @server,
          task_type: "start_instance"
        )

        assert result.success?, result.error
        assert result.value[:simulated]
        assert_predicate result.value[:task], :completed?
        assert_equal true, result.value[:task].result["simulated"]
        assert_predicate @server.reload, :process_state_running?
      end
    end

    test "disabled mode leaves a node task pending" do
      with_developer_mode(enabled: false) do
        result = Minecraft::EnqueueNodeTask.call(
          node: @node,
          server: @server,
          task_type: "start_instance"
        )

        assert result.success?, result.error
        refute result.value[:simulated]
        assert_predicate result.value[:task], :pending?
        assert_predicate @server.reload, :process_state_starting?
      end
    end

    test "remote skin simulation never calls Mojang" do
      profile = Minecraft::PlayerProfile.create!
      identity = Minecraft::PlayerIdentity.create!(
        player_profile: profile,
        platform: "java",
        external_uuid: SecureRandom.uuid,
        username: "Developer",
        identity_type: "primary",
        valid_from: Time.current
      )

      service = Minecraft::RefreshSkin.new(
        uuid: identity.external_uuid,
        platform: identity.platform
      )
      service.define_singleton_method(:fetch_mojang_textures) do |_uuid|
        raise "real Mojang lookup must not run"
      end

      with_developer_mode do
        result = service.call

        assert result.success?, result.error
        assert result.value[:simulated]
        assert_equal profile.public_id, result.value[:player_id]
      end
    end

    private

    def with_developer_mode(enabled: true)
      settings = Mcweb::DeveloperMode.parse(
        config: {
          developer_mode: {
            enabled: enabled,
            preset: "unrestricted"
          }
        },
        environment: {}
      )
      previous = Mcweb::DeveloperMode.instance_variable_get(:@settings)
      Mcweb::DeveloperMode.instance_variable_set(:@settings, settings)
      yield
    ensure
      Mcweb::DeveloperMode.instance_variable_set(:@settings, previous)
    end
  end
end
