# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

module Frontend
  class ApplicationRegistryTest < ActiveSupport::TestCase
    test "CE applications own strict components and method-aware routes" do
      registry = ApplicationRegistry.new(root: Rails.root)

      assert_equal %w[account admin forum staff store website website_preview],
        registry.applications.map(&:id)
      assert_equal "forum", registry.resolve(path: "/app/forum/latest", method: "GET").application_id
      assert_equal "inertia_page", registry.resolve(path: "/app/forum/latest", method: "GET").kind
      assert_equal "application_action", registry.resolve(path: "/app/forum/topics", method: "POST").kind
      assert_equal "download", registry.resolve(path: "/app/store/orders/abc/receipt_pdf", method: "GET").kind
      assert_equal "api", registry.resolve(path: "/app/forum/attachments/abc/scan_status", method: "GET").kind
      assert_equal "download", registry.resolve(path: "/app/forum/topics/abc.rss", method: "GET").kind
      assert_equal "api", registry.resolve(path: "/app/forum/preview", method: "POST").kind
      assert_equal "document", registry.resolve(path: "/app/forum/moderation/approvals", method: "GET").kind
      assert_equal "staff", registry.component_owner("Staff/Forum/Approvals/Index").runtime_application_id
      assert_raises(ApplicationRegistry::ComponentBoundaryViolation) do
        registry.assert_component!(application_id: "forum", component: "Commerce/Products/Index")
      end
    end

    test "downstream fixtures create Channel and extend Staff and Admin without editing CE descriptors" do
      Dir.mktmpdir("frontend-applications") do |directory|
        root = Pathname(directory)
        FileUtils.mkdir_p(root.join("config"))
        FileUtils.cp_r(Rails.root.join("config/frontend_applications"), root.join("config"))
        contribution_root = root.join("config/frontend_applications/contributions")
        FileUtils.mkdir_p(contribution_root)
        Rails.root.glob("test/fixtures/frontend_applications/contributions/*.json").each do |fixture|
          FileUtils.cp(fixture, contribution_root)
        end

        registry = ApplicationRegistry.new(root:)
        assert_equal "channel", registry.launcher_application("/app").id
        assert_equal "channel", registry.component_owner("Ee/Channels/Show").runtime_application_id
        assert_equal "staff", registry.component_owner("Pvp/Staff/Queue/Index").runtime_application_id
        assert_equal "admin", registry.component_owner("Admin/Pvp/Settings/Show").runtime_application_id
        assert_equal "admin", registry.component_owner("Admin/Chat/Settings/Show").runtime_application_id
        assert_equal "pvp", registry.resolve(path: "/app/pvp/tester", method: "GET").application_id
        assert_equal "ee_pvp_astro", registry.fetch_application("website").renderer.adapter
        assert_equal "website", registry.resolve(path: "/legal/terms/service", method: "GET").application_id
        assert_equal "/admin/pvp/settings",
          registry.fetch_application("admin").contributions
            .find { |contribution| contribution.id == "ee_pvp.player.admin" }
            .navigation.first.items.first.href
      end
    end
  end
end
