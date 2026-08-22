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
  end
end
