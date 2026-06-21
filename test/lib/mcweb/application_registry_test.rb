# frozen_string_literal: true

require "test_helper"

class Mcweb::ApplicationRegistryTest < ActiveSupport::TestCase
  test "defines platform modules applications and extensions" do
    assert Mcweb::ApplicationRegistry.platform_modules.any? { |m| m.id == :identity }
    assert Mcweb::ApplicationRegistry.applications.any? { |a| a.id == :forum }
    assert Mcweb::ApplicationRegistry.applications.any? { |a| a.id == :store }
    assert Mcweb::ApplicationRegistry.extensions.any? { |e| e.id == :mcweb_connector }
  end

  test "application_for_path resolves forum and store" do
    assert_equal :forum, Mcweb::ApplicationRegistry.application_for_path("/app/forum/sections").id
    assert_equal :store, Mcweb::ApplicationRegistry.application_for_path("/app/store/products").id
  end

  test "freely extensible is false" do
    assert_not Mcweb::ApplicationRegistry.freely_extensible?
  end

  test "admin catalog includes enabled flag for applications" do
    catalog = Mcweb::ApplicationRegistry.admin_catalog
    forum = catalog[:applications].find { |a| a[:id] == "forum" }

    assert forum
    assert_equal FeatureFlags.enabled?(:forum), forum[:enabled]
  end
end

class AdminSystemApplicationsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "system.settings.manage")
    grant_admin_module(@admin, "system")
  end

  test "applications index for system admin" do
    sign_in_as(@admin)
    get admin_system_applications_path

    assert_response :success
    assert_includes response.body, "applications"
    assert_includes response.body, "forum"
    assert_includes response.body, "mcweb_connector"
  end
end
