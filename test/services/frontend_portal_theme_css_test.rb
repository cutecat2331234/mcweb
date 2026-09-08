# frozen_string_literal: true

require "test_helper"

class FrontendPortalThemeCssTest < ActiveSupport::TestCase
  test "starter theme css does not override portal top nav background" do
    css = Rails.root.join("public/template-starter/styles/theme.css").read

    refute_match(/\.portal-themed header\s*\{/, css, "must not style every header in portal layout")
    refute_includes css, "portal-header", "portal chrome is styled by PortalLayout, not template css"
  end

  test "portal layout skips template css injection to avoid website theme bleed" do
    shell = Rails.root.join(
      "app/javascript/components/application-shell/ApplicationPortalShell.vue"
    ).read
    wrapper = Rails.root.join("app/javascript/layouts/PortalLayout.vue").read

    [ shell, wrapper ].each do |source|
      refute_includes source, "TemplateAssets"
      refute_includes source, "styles/theme.css"
    end
  end

  test "shared portal chrome keeps navigation outside the application content target" do
    source = Rails.root.join(
      "app/javascript/components/application-shell/ApplicationPortalShell.vue"
    ).read

    assert_match(/<LayoutHeader\b/, source)
    assert_match(/<LayoutContent\b[\s\S]*?id="application-content"/, source)
    refute_match(/<header\b/, source)
    refute_match(/<main\b[\s\S]*?<header\b/, source)
  end
end
