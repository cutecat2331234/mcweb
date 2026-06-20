# frozen_string_literal: true

require "test_helper"

class FrontendPortalThemeCssTest < ActiveSupport::TestCase
  test "starter theme css does not override portal top nav background" do
    css = Rails.root.join("public/template-starter/styles/theme.css").read

    refute_match(/\.portal-themed header\s*\{/, css, "must not style every header in portal layout")
    refute_includes css, "portal-header", "portal chrome is styled by PortalLayout, not template css"
  end

  test "portal layout skips template css injection to avoid website theme bleed" do
    source = Rails.root.join("app/javascript/layouts/PortalLayout.vue").read

    assert_includes source, ':include-css="false"'
  end

  test "page header element stays separate from portal top nav" do
    require "nokogiri"
    html = Nokogiri::HTML(<<~HTML)
      <div class="portal-themed">
        <header class="portal-header sticky bg-sidebar">nav</header>
        <main>
          <div class="page-header mb-8 flex flex-col">
            <h1>论坛板块</h1>
            <p>浏览社区讨论分区</p>
          </div>
        </main>
      </div>
    HTML

    page_headers = html.css("main .page-header")
    legacy_headers = html.css("main header")
    scoped = html.css(".portal-themed header.portal-header")

    assert_equal 1, page_headers.size
    assert_empty legacy_headers
    assert_equal 1, scoped.size
    refute_includes scoped, page_headers.first
  end
end
