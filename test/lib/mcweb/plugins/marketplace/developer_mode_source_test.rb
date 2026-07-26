# frozen_string_literal: true

require "test_helper"
require "mcweb/plugins/marketplace"

class Mcweb::Plugins::Marketplace::DeveloperModeSourceTest < ActiveSupport::TestCase
  test "local-only mode rejects HTTPS plugin provenance" do
    with_developer_mode do
      error = assert_raises(Mcweb::Plugins::Marketplace::SourceError) do
        Mcweb::Plugins::Marketplace::PackageSource.new(
          "https://packages.example.test/acme/demo.zip"
        )
      end

      assert_match(/only permits local plugin packages/, error.message)
      source = Mcweb::Plugins::Marketplace::PackageSource.new(
        "file:///tmp/developer-plugin.zip"
      )
      assert_equal "file", source.scheme
    end
  end

  test "disabled mode retains HTTPS package support" do
    with_developer_mode(enabled: false) do
      source = Mcweb::Plugins::Marketplace::PackageSource.new(
        "https://packages.example.test/acme/demo.zip"
      )

      assert_equal "https", source.scheme
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
