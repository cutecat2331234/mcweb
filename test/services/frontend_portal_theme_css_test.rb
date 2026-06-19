# frozen_string_literal: true

require "test_helper"

class FrontendPortalThemeCssTest < ActiveSupport::TestCase
  test "starter theme css scopes portal header background to top nav only" do
    css = Rails.root.join("public/template-starter/styles/theme.css").read

    refute_match(/\.portal-themed header\s*\{/, css, "must not style every header in portal layout")
    assert_includes css, ".portal-themed header.portal-header"
  end

  test "page header element is not matched by scoped portal header rule" do
    require "nokogiri"
    html = Nokogiri::HTML(<<~HTML)
      <div class="portal-themed">
        <header class="portal-header sticky">nav</header>
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
