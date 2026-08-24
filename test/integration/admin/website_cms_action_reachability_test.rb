# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  class WebsiteCmsActionReachabilityTest < ActionDispatch::IntegrationTest
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

    test "read-only website staff do not receive navigation or theme mutation controls" do
      reader = create_user(account_type: "staff")
      grant_permission(reader, "admin.access")
      grant_permission(reader, "website.pages.read")
      grant_permission(reader, "website.articles.read")
      grant_admin_module(reader, "website")
      theme = ::Website::Theme.create!(
        name: "Read-only theme",
        key: "readonly-#{SecureRandom.hex(4)}",
        active: false,
        tokens: {}
      )
      sign_in_as(reader)

      get admin_website_nav_items_path
      assert_response :success
      assert_equal false, inertia.props.deep_symbolize_keys.fetch(:canEdit)

      get admin_website_themes_path
      assert_response :success
      assert_empty inertia.props.deep_symbolize_keys.fetch(:actions)

      get admin_website_theme_path(theme)
      assert_response :success
      actions = inertia.props.deep_symbolize_keys.fetch(:actions)
      assert_equal [ admin_website_theme_revisions_path(theme) ], actions.pluck(:href)
      assert actions.all? { |action| action[:method].blank? }
    end

    test "theme write entry requires read permission" do
      writer = create_user(account_type: "staff")
      grant_permission(writer, "admin.access")
      grant_permission(writer, "website.pages.edit")
      grant_admin_module(writer, "website")
      sign_in_as(writer)

      get new_admin_website_theme_path

      assert_redirected_to root_path
    end

    test "website editors cannot bypass theme publication through form parameters" do
      active_theme = ::Website::Theme.create!(
        name: "Current theme",
        key: "current-#{SecureRandom.hex(4)}",
        active: false,
        tokens: {}
      )
      active_theme.activate!(actor: @editor)
      candidate = ::Website::Theme.create!(
        name: "Candidate theme",
        key: "candidate-#{SecureRandom.hex(4)}",
        active: false,
        tokens: {}
      )

      patch admin_website_theme_path(candidate), params: {
        theme: {
          name: candidate.name,
          key: candidate.key,
          active: true,
          tokens_json: "{}",
          lock_version: candidate.lock_version
        }
      }
      assert_redirected_to admin_website_theme_path(candidate)
      assert_not candidate.reload.active?
      assert active_theme.reload.active?

      created_key = "parameter-active-#{SecureRandom.hex(4)}"
      post admin_website_themes_path, params: {
        theme: {
          name: "Parameter active theme",
          key: created_key,
          active: true,
          tokens_json: "{}"
        }
      }
      created_theme = ::Website::Theme.find_by!(key: created_key)
      assert_not created_theme.active?
      assert_equal [ active_theme.id ], ::Website::Theme.active_themes.pluck(:id)
    end

    test "website editors can update navigation but cannot orphan immutable Theme history" do
      item = ::Website::NavItem.create!(
        label: "Before update",
        url: "/before",
        location: "header",
        visible: true,
        position: 0
      )

      patch admin_website_nav_item_path(item), params: {
        nav_item: {
          label: "Invalid update",
          url: "/invalid",
          website_page_id: "missing-page-#{SecureRandom.hex(4)}",
          location: "footer",
          visible: false
        }
      }
      assert_redirected_to admin_website_nav_items_path
      assert_equal "Before update", item.reload.label

      patch admin_website_nav_item_path(item), params: {
        nav_item: {
          label: "After update",
          url: "/after",
          website_page_id: nil,
          location: "footer",
          visible: false
        }
      }
      assert_redirected_to admin_website_nav_items_path
      item.reload
      assert_equal "After update", item.label
      assert_equal "/after", item.url
      assert_equal "footer", item.location
      assert_not item.visible?

      created = ::Website::MutateTheme.call(
        operation: :create,
        theme: ::Website::Theme.new,
        actor: @editor,
        attributes: {
          name: "Governed theme",
          key: "governed-delete-#{SecureRandom.hex(4)}",
          tokens: {}
        }
      )
      assert_predicate created, :success?, created.error
      theme = created.value.fetch(:theme)
      discarded_page = ::Website::Page.create!(
        title: "Discarded themed page",
        slug: "discarded-themed-page-#{SecureRandom.hex(4)}",
        page_type: "custom",
        status: "draft",
        author: @editor,
        theme: theme
      )
      discarded_page.update_columns(
        discarded_at: Time.current,
        discarded_by_id: @editor.id,
        discard_reason: "Theme deletion coverage",
        discard_idempotency_key_digest: SecureRandom.hex(32),
        purge_at: 30.days.from_now
      )

      get edit_admin_website_theme_path(theme)
      assert_response :success
      assert_nil inertia.props.deep_symbolize_keys.fetch(:deleteUrl)

      delete admin_website_theme_path(theme)
      assert_redirected_to admin_website_theme_path(theme)
      assert ::Website::Theme.exists?(theme.id)
      assert_equal theme.id,
                   ::Website::Page.with_lifecycle.find(discarded_page.id).website_theme_id
      assert_predicate theme.revisions, :exists?
    end

    test "lifecycle revision deep links return read-only staff to an authorized list" do
      reader = create_user(account_type: "staff")
      grant_permission(reader, "admin.access")
      grant_permission(reader, "website.pages.read")
      grant_permission(reader, "website.articles.read")
      grant_admin_module(reader, "website")
      page = ::Website::Page.create!(
        title: "Discarded page",
        slug: "discarded-page-#{SecureRandom.hex(4)}",
        page_type: "custom",
        status: "draft",
        author: reader
      )
      article = ::Website::Article.create!(
        title: "Discarded article",
        slug: "discarded-article-#{SecureRandom.hex(4)}",
        article_type: "news",
        status: "draft",
        author: reader
      )
      lifecycle_fields = {
        discarded_at: Time.current,
        discarded_by_id: reader.id,
        discard_reason: "Permission return-path check",
        purge_at: 30.days.from_now
      }
      page.update_columns(lifecycle_fields.merge(discard_idempotency_key_digest: SecureRandom.hex(32)))
      article.update_columns(lifecycle_fields.merge(discard_idempotency_key_digest: SecureRandom.hex(32)))
      sign_in_as(reader)

      get admin_website_page_revisions_path(page)
      assert_response :success
      assert_equal admin_website_pages_path,
                   inertia.props.deep_symbolize_keys.fetch(:backUrl)

      get admin_website_article_revisions_path(article)
      assert_response :success
      assert_equal admin_website_articles_path,
                   inertia.props.deep_symbolize_keys.fetch(:backUrl)
    end
  end
end
