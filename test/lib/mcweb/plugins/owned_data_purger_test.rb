# frozen_string_literal: true

require "test_helper"
require "mcweb/plugins/owned_data_purger"
require "mcweb/plugin_api/v1/host"

class Mcweb::Plugins::OwnedDataPurgerTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @host = host("acme/purge")
    @other = host("other/keep")
  end

  test "explicit purge removes only the selected plugin host-owned data" do
    create_outbound(@host, "purge")
    create_outbound(@other, "keep")
    create_storage(@host, "purge.txt")
    create_storage(@other, "keep.txt")
    create_setting("acme/purge")
    create_setting("other/keep")

    counts = Mcweb::Plugins::OwnedDataPurger.call(plugin_id: "acme/purge")

    assert_equal 1, counts.fetch("plugin_outbound_deliveries")
    assert_equal 1, counts.fetch("plugin_storage_objects")
    assert_equal 1, counts.fetch("plugin_setting_versions")
    assert_equal 0, PluginOutboundDelivery.where(owner_plugin_id: "acme/purge").count
    assert_equal 0, PluginStorageObject.where(owner_plugin_id: "acme/purge").count
    assert_equal 0, PluginSettingVersion.where(plugin_id: "acme/purge").count
    assert_equal 1, PluginOutboundDelivery.where(owner_plugin_id: "other/keep").count
    assert_equal 1, PluginStorageObject.where(owner_plugin_id: "other/keep").count
    assert_equal 1, PluginSettingVersion.where(plugin_id: "other/keep").count
  end

  test "invalid plugin ids fail before touching data" do
    error = assert_raises(ArgumentError) do
      Mcweb::Plugins::OwnedDataPurger.call(plugin_id: "../all")
    end
    assert_equal "invalid plugin id", error.message
  end

  private

  def host(plugin_id)
    manifest = Mcweb::Plugins::Manifest.from_hash({
      id: plugin_id,
      name: plugin_id,
      version: "1.0.0",
      api_version: "1"
    })
    Mcweb::PluginApi::V1::Host.new(manifest:, event_bus: Mcweb::Events)
  end

  def create_outbound(host, suffix)
    result = host.notifications.deliver(
      user: @user,
      notification_type: "test",
      title: "Test",
      idempotency_key: "notice-#{suffix}"
    )
    assert_predicate result, :success?
  end

  def create_storage(host, key)
    result = host.storage.put(key:, data: key)
    assert_predicate result, :success?
  end

  def create_setting(plugin_id)
    PluginSettingVersion.create!(
      plugin_id:,
      schema_version: "1",
      schema_digest: Digest::SHA256.hexdigest("schema"),
      revision: 1,
      change_kind: "update",
      values: { "enabled" => true }
    )
  end
end
