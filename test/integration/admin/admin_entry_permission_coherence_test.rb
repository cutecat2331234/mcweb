# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  class ArcoDemoAccessTest < ActionDispatch::IntegrationTest
    test "the static Arco demo stays hidden while Developer Mode is disabled" do
      Mcweb::DeveloperMode.stub(:enabled?, false) do
        get admin_arco_demo_path
        assert_response :not_found

        get admin_dashboard_pro_demo_path
        assert_response :not_found

        get admin_store_orders_pro_demo_path
        assert_response :not_found
      end
    end

    test "authorized admins can use the static Arco demo in Developer Mode" do
      admin = create_user
      grant_permission(admin, "admin.access")
      sign_in_as(admin)

      Mcweb::DeveloperMode.stub(:enabled?, true) do
        get admin_arco_demo_path

        assert_response :success
        assert_equal "Admin/ArcoDemo/Index", inertia.component
        assert_equal true, inertia.props.deep_symbolize_keys.fetch(:admin_demo_enabled)
      end
    end
  end

  class AdminEntryPermissionCoherenceTest < ActionDispatch::IntegrationTest
    test "page editing permission without read permission has no form or write entry" do
      editor = website_editor_with("website.pages.edit")
      page = build_page(author: editor)

      get new_admin_website_page_path
      assert_redirected_to root_path

      get edit_admin_website_page_path(page)
      assert_redirected_to root_path

      patch admin_website_page_path(page), params: {
        page: {
          title: "Hidden update",
          slug: page.slug,
          page_type: page.page_type
        }
      }
      assert_redirected_to root_path
      assert_equal "Permission page", page.reload.title

      post admin_website_page_blocks_path(page), params: {
        block: { block_type: "hero", visible: true, settings: { headline: "Hidden" } }
      }
      assert_redirected_to root_path
      assert_empty page.blocks

      post admin_website_nav_items_path, params: {
        nav_item: { label: "Hidden", website_page_id: page.public_id, location: "header" }
      }
      assert_redirected_to root_path
      assert_empty ::Website::NavItem.where(label: "Hidden")
    end

    test "article editing permission without read permission has no form or write entry" do
      editor = website_editor_with("website.articles.edit")
      article = build_article(author: editor)

      get new_admin_website_article_path
      assert_redirected_to root_path

      get edit_admin_website_article_path(article)
      assert_redirected_to root_path

      patch admin_website_article_path(article), params: {
        article: {
          title: "Hidden update",
          slug: article.slug,
          article_type: article.article_type
        }
      }
      assert_redirected_to root_path
      assert_equal "Permission article", article.reload.title
    end

    test "identity group management permission without read permission has no form or write entry" do
      manager = create_user
      grant_permission(manager, "admin.access")
      grant_permission(manager, "identity.groups.manage")
      sign_in_as(manager)
      group = Community::UserGroup.create!(name: "Permission group", priority: 1)

      get new_admin_forum_user_group_path
      assert_redirected_to root_path

      get edit_admin_forum_user_group_path(group)
      assert_redirected_to root_path

      patch admin_forum_user_group_path(group), params: {
        user_group: {
          name: "Hidden update",
          priority: group.priority,
          is_primary_default: false
        }
      }
      assert_redirected_to root_path
      assert_equal "Permission group", group.reload.name
    end

    private

    def website_editor_with(permission_key)
      editor = create_user
      grant_permission(editor, "admin.access")
      grant_permission(editor, permission_key)
      sign_in_as(editor)
      editor
    end

    def build_page(author:)
      ::Website::Page.create!(
        public_id: "page_permission_#{SecureRandom.hex(4)}",
        title: "Permission page",
        slug: "permission-page-#{SecureRandom.hex(4)}",
        page_type: "custom",
        status: "draft",
        author: author
      )
    end

    def build_article(author:)
      ::Website::Article.create!(
        public_id: "article_permission_#{SecureRandom.hex(4)}",
        title: "Permission article",
        slug: "permission-article-#{SecureRandom.hex(4)}",
        article_type: "news",
        status: "draft",
        author: author
      )
    end
  end

  class WebsiteCmsEntryTest < ActionDispatch::IntegrationTest
    setup do
      @editor = create_user(account_type: "staff")
      grant_permission(@editor, "admin.access")
      grant_permission(@editor, "website.pages.read")
      grant_permission(@editor, "website.pages.edit")
      grant_permission(@editor, "website.articles.read")
      grant_permission(@editor, "website.articles.edit")
      grant_permission(@editor, "website.content.restore")
      grant_admin_module(@editor, "website")
      sign_in_as(@editor)
    end

    test "authorized website staff can open every CMS menu destination" do
      {
        admin_website_pages_path => "Admin/Generic/Index",
        admin_website_articles_path => "Admin/Generic/Index",
        admin_website_nav_items_path => "Admin/Website/NavItems/Index",
        admin_website_themes_path => "Admin/Generic/Index",
        admin_website_recycle_bin_path => "Admin/Website/Recovery/Index"
      }.each do |path, component|
        get path

        failure_detail = response.body[%r{<div class="message">(.*?)</div>}m, 1]
          .to_s
          .gsub(%r{<[^>]+>}, " ")
          .squish
        assert_response :success,
                        "expected #{path} to load, got #{response.status}: #{failure_detail}"
        assert_equal component, inertia.component, "expected #{path} to render #{component}"
      end
    end

    test "CMS page, article, revision, and preview direct links resolve through their owning entry" do
      page = ::Website::Page.create!(
        title: "Reachable page",
        slug: "reachable-page-#{SecureRandom.hex(4)}",
        page_type: "custom",
        status: "draft",
        author: @editor
      )
      article = ::Website::Article.create!(
        title: "Reachable article",
        slug: "reachable-article-#{SecureRandom.hex(4)}",
        article_type: "news",
        status: "draft",
        author: @editor
      )

      {
        new_admin_website_page_path => "Admin/Website/Pages/Form",
        edit_admin_website_page_path(page) => "Admin/Website/Pages/Form",
        admin_website_page_revisions_path(page) => "Admin/Website/Revisions/Index",
        new_admin_website_article_path => "Admin/Website/Articles/Form",
        edit_admin_website_article_path(article) => "Admin/Website/Articles/Form",
        admin_website_article_revisions_path(article) => "Admin/Website/Revisions/Index"
      }.each do |path, component|
        get path
        assert_response :success, "expected #{path} to open"
        assert_equal component, inertia.component
      end

      get preview_admin_website_page_path(page)
      assert_response :success
      assert_equal "Website/Pages/Show", inertia.component

      get preview_admin_website_article_path(article)
      assert_response :success
      assert_equal "Website/Articles/Show", inertia.component
    end

    test "purge permission remains independent while the recycle bin still enforces content read access" do
      purger = create_user(account_type: "staff")
      grant_permission(purger, "admin.access")
      grant_permission(purger, "website.content.purge")
      grant_permission(purger, "website.pages.read")
      grant_admin_module(purger, "website")
      sign_in_as(purger)

      get admin_website_recycle_bin_path

      assert_response :success
      assert_equal "Admin/Website/Recovery/Index", inertia.component
      props = inertia.props.deep_symbolize_keys
      assert_equal admin_website_pages_path, props.fetch(:pagesUrl)
      assert_nil props.fetch(:articlesUrl)
    end
  end
end
