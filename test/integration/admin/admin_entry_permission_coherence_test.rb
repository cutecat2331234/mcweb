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
end
