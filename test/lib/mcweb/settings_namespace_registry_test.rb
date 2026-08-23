# frozen_string_literal: true

require "test_helper"

module Mcweb
  class SettingsNamespaceRegistryTest < ActiveSupport::TestCase
    test "the registry is loaded before downstream initializers run" do
      source = Rails.root.join("config/application.rb").read

      assert_includes source, 'require_relative "../lib/mcweb/settings_namespace_registry"'
      assert defined?(Mcweb::SettingsNamespaceRegistry::DEFAULT)
    end

    test "longest matching namespace owns a setting" do
      registry = SettingsNamespaceRegistry::Registry.new
      registry.register(prefix: "product.", owner: "platform")
      registry.register(prefix: "product.policy.", owner: "policy.console")

      assert_equal "policy.console", registry.owner_for("product.policy.version")
      assert_equal "platform", registry.owner_for("product.label")
      assert_nil registry.owner_for("unrelated.product")
    end

    test "registration is idempotent for the same owner and rejects conflicts" do
      registry = SettingsNamespaceRegistry::Registry.new
      first = registry.register(prefix: "product.", owner: "platform")

      assert_same first, registry.register(prefix: "product.", owner: "platform")
      assert_raises(ArgumentError) do
        registry.register(prefix: "product.", owner: "different.owner")
      end
    end

    test "invalid prefixes and owner identifiers are rejected" do
      registry = SettingsNamespaceRegistry::Registry.new

      assert_raises(ArgumentError) do
        registry.register(prefix: "Product", owner: "platform")
      end
      assert_raises(ArgumentError) do
        registry.register(prefix: "product.", owner: "")
      end
    end

    test "registered namespaces fail closed unless a key belongs to the requested surface" do
      registry = SettingsNamespaceRegistry::Registry.new
      registry.register(prefix: "forum.", owner: "admin.forum.settings")
      registry.register_setting(
        key: "forum.digest_hour",
        type: :integer,
        constraints: { min: 0, max: 23 }
      )

      refute registry.visible_on?("forum.digest_hour", surface: :generic)
      refute registry.writable_on?("forum.future_setting", surface: :generic)
      assert registry.visible_on?("custom.extension.label", surface: :generic)
    end

    test "setting registrations normalize typed values and reject invalid values" do
      registry = SettingsNamespaceRegistry::Registry.new
      registry.register(prefix: "site.", owner: "admin.system.settings", surface: :basic)
      registry.register_setting(
        key: "site.retries",
        type: :integer,
        constraints: { min: 1, max: 5 }
      )

      assert_equal "3", registry.normalize_for_write(
        "site.retries",
        "03",
        surface: :basic,
        owner: "admin.system.settings"
      )
      error = assert_raises(SettingsNamespaceRegistry::ValidationError) do
        registry.normalize_for_write(
          "site.retries",
          "six",
          surface: :basic,
          owner: "admin.system.settings"
        )
      end
      assert_equal "invalid_integer", error.code
      assert_equal "site.retries", error.key
      refute_includes error.message, "six"
    end

    test "sensitivity is explicit and falls back safely for legacy custom secrets" do
      registry = SettingsNamespaceRegistry::Registry.new
      registry.register(prefix: "store.", owner: "admin.store.settings")
      registry.register_setting(
        key: "store.webhook_credential",
        sensitivity: :secret
      )

      assert registry.sensitive?("store.webhook_credential")
      assert registry.sensitive?("custom.delivery_token")
      refute registry.sensitive?("custom.delivery_label")
    end
  end
end
