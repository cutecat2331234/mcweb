# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

class PluginContributionPagesTest < ActionDispatch::IntegrationTest
  Entry = Data.define(:id, :plugin_id, :payload)

  setup do
    @admin = create_user(account_type: "admin")
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "plugin.demo.view")
  end

  test "public plugin pages and navigation render only safe declarative blocks" do
    with_contributions do
      get "/plugins/acme/demo/overview"

      assert_response :success
      assert_inertia_component "Plugins/Page"
      props = inertia.props.deep_symbolize_keys
      assert_equal "Demo overview", props.dig(:pluginPage, :title)
      assert_equal %w[stat links], props.dig(:pluginPage, :blocks).pluck(:type)
      navigation = props.dig(:plugin_contributions, :navigation, :public)
      assert_equal "/plugins/acme/demo/overview", navigation.sole.fetch(:href)
      refute_includes response.body, "acme.demo.page.title"
      refute_includes response.body, "alert(1)"
      refute_includes response.body, "raw_html"
    end
  end

  test "admin pages and targeted slots require their declared permission" do
    sign_in_as(@admin)
    with_contributions do
      get "/admin/plugins/acme/demo/overview"

      assert_response :success
      assert_inertia_component "Admin/Plugins/Page"
      props = inertia.props.deep_symbolize_keys
      assert_equal "Demo admin", props.dig(:pluginPage, :title)
      assert_equal "Build status", props.dig(:plugin_contributions, :ui_slots, 0, :title)

      permission = Permission.find_by!(key: "plugin.demo.view")
      @admin.roles
        .joins(:permissions)
        .where(permissions: { id: permission.id })
        .each { |role| @admin.roles.delete(role) }

      get "/admin/plugins/acme/demo/overview"
      assert_response :not_found
    end
  end

  test "unknown and cross-surface routes are hidden as not found" do
    with_contributions do
      get "/plugins/acme/demo/missing"
      assert_response :not_found

      get "/plugins/acme/demo/admin"
      assert_response :not_found
    end
  end

  private

  def with_contributions(&)
    catalog = contribution_catalog
    provider = ->(type:) { catalog.fetch(type.to_s, []) }
    Mcweb::Plugins.stub(:contributions, provider, &)
  end

  def contribution_catalog
    {
      "navigation" => [
        entry(
          "navigation",
          "nav.public",
          "surface" => "public",
          "position" => "header",
          "label_phrase" => "acme.demo.nav.label",
          "href" => "/plugins/acme/demo/overview"
        ),
        entry(
          "navigation",
          "nav.admin",
          "surface" => "admin",
          "position" => "sidebar",
          "label_phrase" => "acme.demo.nav.admin",
          "href" => "/admin/plugins/acme/demo/overview",
          "permission" => "plugin.demo.view"
        )
      ],
      "page" => [
        entry(
          "page",
          "page.public",
          "surface" => "public",
          "path" => "/plugins/acme/demo/overview",
          "title_phrase" => "acme.demo.page.title",
          "blocks" => [
            {
              "type" => "stat",
              "label_phrase" => "acme.demo.stat.label",
              "value" => 42
            },
            {
              "type" => "links",
              "items" => [
                {
                  "label_phrase" => "acme.demo.link.label",
                  "href" => "/app"
                },
                {
                  "label_phrase" => "acme.demo.link.unsafe",
                  "href" => "https://evil.example"
                }
              ]
            },
            {
              "type" => "raw_html",
              "body" => "<script>alert(1)</script>"
            }
          ]
        ),
        entry(
          "page",
          "page.admin",
          "surface" => "admin",
          "path" => "/admin/plugins/acme/demo/overview",
          "title_phrase" => "acme.demo.page.admin",
          "permission" => "plugin.demo.view",
          "blocks" => []
        )
      ],
      "ui_slot" => [
        entry(
          "ui_slot",
          "slot.admin",
          "slot" => "dashboard.cards",
          "kind" => "card",
          "target" => "/admin/plugins/acme/demo/overview",
          "title_phrase" => "acme.demo.slot.title",
          "permission" => "plugin.demo.view",
          "schema" => {
            "description_phrase" => "acme.demo.slot.description",
            "value" => 1
          }
        )
      ],
      "translation" => [
        entry(
          "translation",
          "translation.en",
          "locale" => "en",
          "phrases" => {
            "acme.demo.nav.label" => "Demo",
            "acme.demo.nav.admin" => "Demo admin",
            "acme.demo.page.title" => "Demo overview",
            "acme.demo.page.admin" => "Demo admin",
            "acme.demo.stat.label" => "Completed",
            "acme.demo.link.label" => "Open application",
            "acme.demo.link.unsafe" => "Unsafe",
            "acme.demo.slot.title" => "Build status",
            "acme.demo.slot.description" => "Ready"
          }
        )
      ]
    }
  end

  def entry(type, suffix, payload)
    Entry.new(
      id: "acme.demo.#{suffix}",
      plugin_id: "acme/demo",
      payload:
    )
  end
end
