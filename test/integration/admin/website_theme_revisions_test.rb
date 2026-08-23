# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  class WebsiteThemeRevisionsTest < ActionDispatch::IntegrationTest
    setup do
      @admin = create_user(account_type: "staff")
      grant_permission(@admin, "admin.access")
      grant_permission(@admin, "website.pages.read")
      grant_permission(@admin, "website.pages.edit")
      grant_permission(@admin, "website.content.restore")
      grant_admin_module(@admin, "website")
      sign_in_as(@admin)
      created = ::Website::MutateTheme.call(
        operation: :create,
        theme: ::Website::Theme.new,
        actor: @admin,
        attributes: {
          name: "Revision UI Theme",
          key: "revision-ui-#{SecureRandom.hex(4)}",
          tokens: { "color" => { "primary" => "#123456" } }
        }
      )
      assert_predicate created, :success?, created.error
      @theme = created.value.fetch(:theme)
    end

    test "history pagination is anchored and revision props omit internal digests" do
      2.upto(31) do |number|
        ::Website::ThemeRevision.create!(
          theme: @theme,
          actor: @admin,
          revision_number: number,
          snapshot: {
            "name" => "Revision #{number}",
            "key" => @theme.key,
            "tokens" => { "sequence" => number },
            "active" => false
          },
          event_type: "update",
          source_lock_version: @theme.lock_version
        )
      end

      get admin_website_theme_revisions_path(@theme)
      assert_response :success
      props = inertia.props.deep_symbolize_keys
      assert_equal 31, props.dig(:pagination, :anchor)
      assert_equal 25, props.fetch(:revisions).length
      assert_equal((7..31).to_a.reverse, props.fetch(:revisions).pluck(:revisionNumber))
      safe_summaries = props.fetch(:revisions).all? do |revision|
        (revision.keys & %i[request_id_digest operation_digest source_lock_version]).empty?
      end
      assert safe_summaries

      ::Website::ThemeRevision.create!(
        theme: @theme,
        actor: @admin,
        revision_number: 32,
        snapshot: {
          "name" => "Inserted after page one",
          "key" => @theme.key,
          "tokens" => {},
          "active" => false
        },
        event_type: "update",
        source_lock_version: @theme.lock_version
      )

      get admin_website_theme_revisions_path(@theme), params: { page: 2, anchor: 31 }
      assert_response :success
      anchored = inertia.props.deep_symbolize_keys
      assert_equal [ 6, 5, 4, 3, 2, 1 ], anchored.fetch(:revisions).pluck(:revisionNumber)
      assert_equal 31, anchored.dig(:pagination, :count)

      get admin_website_theme_revisions_path(@theme), params: { page: 99, anchor: 31 }
      assert_response :found
      assert_includes response.location, "page=2"
      assert_includes response.location, "anchor=31"
    end

    test "revision detail returns only whitelisted snapshot and difference fields" do
      first_update = ::Website::MutateTheme.call(
        operation: :update,
        theme: @theme,
        actor: @admin,
        expected_lock_version: @theme.lock_version,
        attributes: {
          name: "Revision UI Theme Two",
          key: @theme.key,
          tokens: { "color" => { "primary" => "#abcdef" } }
        }
      )
      assert_predicate first_update, :success?, first_update.error
      second_update = ::Website::MutateTheme.call(
        operation: :update,
        theme: @theme,
        actor: @admin,
        expected_lock_version: @theme.reload.lock_version,
        attributes: {
          name: "Revision UI Theme Three",
          key: @theme.key,
          tokens: { "color" => { "primary" => "#fedcba" } }
        }
      )
      assert_predicate second_update, :success?, second_update.error
      revision = second_update.value.fetch(:revision)

      get admin_website_theme_revision_path(@theme, revision.revision_number)

      assert_response :success
      props = inertia.props.deep_symbolize_keys
      serialized = props.fetch(:revision)
      assert_equal %i[active key name tokens], serialized.fetch(:snapshot).keys.sort
      assert serialized.fetch(:difference).any? { |change| change[:path] == "name" }
      assert serialized.fetch(:difference).any? { |change| change[:path] == "tokens.color.primary" }
      assert_empty serialized.keys & %i[requestIdDigest operationDigest sourceLockVersion websiteThemeId]
      assert_equal @theme.reload.lock_version, props.dig(:theme, :lockVersion)
    end

    test "restore endpoint requires edit and content restore permissions together" do
      source = @theme.revisions.first
      editor = create_user(account_type: "staff")
      grant_permission(editor, "admin.access")
      grant_permission(editor, "website.pages.read")
      grant_permission(editor, "website.pages.edit")
      grant_admin_module(editor, "website")
      sign_in_as(editor)

      post restore_admin_website_theme_revision_path(@theme, source.revision_number), params: {
        reason: "Permission intersection",
        confirmation: source.revision_number.to_s,
        lock_version: @theme.lock_version,
        request_id: "theme-permission-#{SecureRandom.uuid}"
      }

      assert_redirected_to root_path
      assert_equal 1, @theme.revisions.count
    end

    test "permitted restore redirects to the immutable successor revision" do
      source = @theme.revisions.first
      changed = ::Website::MutateTheme.call(
        operation: :update,
        theme: @theme,
        actor: @admin,
        expected_lock_version: @theme.lock_version,
        attributes: {
          name: "Temporary UI Theme",
          key: @theme.key,
          tokens: { "temporary" => true }
        }
      )
      assert_predicate changed, :success?, changed.error

      post restore_admin_website_theme_revision_path(@theme, source.revision_number), params: {
        reason: "Restore the reviewed UI version",
        confirmation: source.revision_number.to_s,
        lock_version: @theme.reload.lock_version,
        request_id: "theme-controller-#{SecureRandom.uuid}"
      }

      successor = @theme.revisions.ordered.first
      assert_equal "restore", successor.event_type
      assert_redirected_to admin_website_theme_revision_path(@theme, successor.revision_number)
      assert_equal "Revision UI Theme", @theme.reload.name
    end
  end
end
