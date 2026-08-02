# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  module Forum
    class ForumSectionsPermissionBoundariesTest < ActionDispatch::IntegrationTest
      setup do
        suffix = SecureRandom.hex(5)
        @category = Community::Category.create!(
          name: "Permission boundaries #{suffix}",
          slug: "permission-boundaries-#{suffix}"
        )
        @section = Community::Section.create!(
          category: @category,
          name: "Permission boundary section",
          slug: "permission-boundary-section-#{suffix}",
          position: 0
        )
      end

      test "manage permission can browse lifecycle state but cannot mutate it" do
        sign_in_with_permissions("forum.sections.manage")

        get admin_forum_sections_path
        assert_response :success

        get admin_forum_section_path(@section.id)
        assert_response :success
        actions = inertia.props.deep_symbolize_keys.fetch(:actions)
        assert actions.any? { |action| action[:href] == edit_admin_forum_section_path(@section.id) }

        get lifecycle_admin_forum_section_path(@section.id)
        assert_response :success
        props = inertia.props.deep_symbolize_keys
        assert_not props.fetch(:canManageLifecycle)
        assert_not props.fetch(:canDelete)

        patch archive_admin_forum_section_path(@section.id), params: {
          reason: "Should be rejected",
          confirmation: "ARCHIVE #{@section.slug}"
        }
        assert_redirected_to root_path
        assert_nil @section.reload.archived_at

        assert_no_difference "Community::Section.count" do
          delete admin_forum_section_path(@section.id), params: {
            reason: "Should be rejected",
            confirmation: "DELETE #{@section.slug}"
          }
        end
        assert_redirected_to root_path
      end

      test "lifecycle permission archives and restores but cannot permanently delete" do
        sign_in_with_permissions("forum.sections.lifecycle")

        get admin_forum_sections_path
        assert_response :success
        assert_empty inertia.props.deep_symbolize_keys.fetch(:actions)

        get admin_forum_section_path(@section.id)
        assert_response :success
        actions = inertia.props.deep_symbolize_keys.fetch(:actions)
        assert actions.none? { |action| action[:href] == edit_admin_forum_section_path(@section.id) }

        get lifecycle_admin_forum_section_path(@section.id)
        assert_response :success
        props = inertia.props.deep_symbolize_keys
        assert props.fetch(:canManageLifecycle)
        assert_not props.fetch(:canDelete)

        patch archive_admin_forum_section_path(@section.id), params: {
          reason: "Lifecycle operator archive",
          confirmation: "ARCHIVE #{@section.slug}"
        }
        assert_redirected_to lifecycle_admin_forum_section_path(@section.id)
        assert_predicate @section.reload.archived_at, :present?

        assert_no_difference "Community::Section.count" do
          delete admin_forum_section_path(@section.id), params: {
            reason: "Lifecycle operator delete",
            confirmation: "DELETE #{@section.slug}"
          }
        end
        assert_redirected_to root_path

        patch restore_admin_forum_section_path(@section.id), params: {
          reason: "Lifecycle operator restore",
          confirmation: "RESTORE #{@section.slug}"
        }
        assert_redirected_to lifecycle_admin_forum_section_path(@section.id)
        assert_nil @section.reload.archived_at
      end

      test "delete permission can permanently delete an eligible archived section" do
        @section.update_columns(
          archived_at: Time.current,
          archived_reason: "Prepared for deletion"
        )
        sign_in_with_permissions("forum.sections.delete")

        get admin_forum_sections_path
        assert_response :success
        get admin_forum_section_path(@section.id)
        assert_response :success
        get lifecycle_admin_forum_section_path(@section.id)
        assert_response :success
        props = inertia.props.deep_symbolize_keys
        assert_not props.fetch(:canManageLifecycle)
        assert props.fetch(:canDelete)

        assert_difference "Community::Section.count", -1 do
          delete admin_forum_section_path(@section.id), params: {
            reason: "Duplicate section",
            confirmation: "DELETE #{@section.slug}"
          }
        end
        assert_redirected_to admin_forum_sections_path
      end

      private

      def sign_in_with_permissions(*permission_keys)
        operator = create_user(account_type: "admin")
        grant_permission(operator, "admin.access")
        permission_keys.each { |key| grant_permission(operator, key) }
        sign_in_as(operator)
      end
    end
  end
end
