# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  module Forum
    class ForumSectionsLifecycleAdminTest < ActionDispatch::IntegrationTest
      setup do
        suffix = SecureRandom.hex(5)
        @admin = create_user(username: "section_admin_#{suffix}", account_type: "admin")
        grant_permission(@admin, "admin.access")
        grant_permission(@admin, "forum.sections.manage")
        grant_permission(@admin, "forum.sections.lifecycle")
        grant_permission(@admin, "forum.sections.delete")
        grant_permission(@admin, "forum.topics.move")
        @category = Community::Category.create!(
          name: "Admin lifecycle #{suffix}",
          slug: "admin-lifecycle-#{suffix}"
        )
        @section = Community::Section.create!(
          category: @category,
          name: "Admin lifecycle section",
          slug: "admin-lifecycle-section-#{suffix}",
          position: 0
        )
        sign_in_as(@admin)
      end

      test "index and lifecycle page expose status impact blockers and typed confirmations" do
        get admin_forum_sections_path

        assert_response :success
        assert_equal "Admin/Generic/Index", inertia.component
        row = inertia.props.deep_symbolize_keys.fetch(:rows).find { |item| item[:name] == @section.name }
        assert_equal I18n.t("mcweb.admin.forum.sections.status_effectively_active"), row.fetch(:status)
        assert_equal admin_forum_section_path(@section.id), row.fetch(:url)

        get lifecycle_admin_forum_section_path(@section.id)

        assert_response :success
        assert_equal "Admin/Forum/Sections/Lifecycle", inertia.component
        props = inertia.props.deep_symbolize_keys
        assert_equal @section.slug, props.dig(:section, :slug)
        assert_equal 1, props.dig(:impact, :sections)
        assert_includes props.fetch(:destroyBlockers), I18n.t("mcweb.admin.forum.sections.blocker_not_archived")
        assert_equal "ARCHIVE #{@section.slug}", props.dig(:confirmations, :archive)
        assert_equal "DELETE #{@section.slug}", props.dig(:confirmations, :destroy)
        assert props.dig(:section, :effectively_active)
        assert props.fetch(:canDelete)
      end

      test "admin archives and restores through audited lifecycle endpoints" do
        assert_difference -> { AuditLog.where(action: "admin.forum_section_archived").count }, 1 do
          patch archive_admin_forum_section_path(@section.id), params: {
            reason: "Seasonal section retired",
            confirmation: "ARCHIVE #{@section.slug}"
          }
        end

        assert_redirected_to lifecycle_admin_forum_section_path(@section.id)
        assert_predicate @section.reload.archived_at, :present?
        assert_predicate AuditLog.find_by!(
          action: "admin.forum_section_archived",
          resource_id: @section.id
        ).request_id, :present?

        assert_difference -> { AuditLog.where(action: "admin.forum_section_restored").count }, 1 do
          patch restore_admin_forum_section_path(@section.id), params: {
            reason: "New season opened",
            confirmation: "RESTORE #{@section.slug}"
          }
        end

        assert_redirected_to lifecycle_admin_forum_section_path(@section.id)
        assert_nil @section.reload.archived_at
      end

      test "index distinguishes and filters inherited archive state" do
        child = Community::Section.create!(
          category: @category,
          parent: @section,
          name: "Inherited archive child",
          slug: "inherited-archive-child-#{SecureRandom.hex(4)}",
          position: 1
        )
        Community::ManageSectionLifecycle.call(
          section: @section,
          actor: @admin,
          operation: "archive",
          reason: "Retire branch",
          confirmation: "ARCHIVE #{@section.slug}"
        )

        get admin_forum_sections_path(status: "inherited_archived")

        assert_response :success
        props = inertia.props.deep_symbolize_keys
        assert_equal [ child.name ], props.fetch(:rows).pluck(:name)
        assert_equal I18n.t("mcweb.admin.forum.sections.status_inherited_archived"),
          props.fetch(:rows).sole.fetch(:status)
        inherited_tab = props.fetch(:statusTabs).find { |tab| tab[:active] }
        assert_equal 1, inherited_tab.fetch(:count)

        get lifecycle_admin_forum_section_path(child.id)
        lifecycle_props = inertia.props.deep_symbolize_keys
        assert lifecycle_props.dig(:section, :inherited_archived)
        assert_not lifecycle_props.dig(:section, :effectively_active)
        assert_equal @section.id, lifecycle_props.dig(:section, :archived_ancestor, :id)
      end

      test "admin migrates topics out of an archived branch without exposing its public route" do
        target = Community::Section.create!(
          category: @category,
          name: "Active migration target",
          slug: "active-migration-target-#{SecureRandom.hex(4)}",
          position: 2
        )
        topic = Community::Topic.create!(
          public_id: "topic_#{SecureRandom.alphanumeric(16)}",
          section: @section,
          user: @admin,
          title: "Retained archived topic",
          status: "published",
          last_posted_at: Time.current,
          last_post_user: @admin,
          replies_count: 0
        )
        Community::ManageSectionLifecycle.call(
          section: @section,
          actor: @admin,
          operation: "archive",
          reason: "Retire source",
          confirmation: "ARCHIVE #{@section.slug}"
        )

        get forum_topic_path(topic)
        assert_response :not_found

        patch migrate_topics_admin_forum_section_path(@section.id), params: {
          target_section_id: target.id,
          reason: "Move retained content to the active destination"
        }

        assert_redirected_to lifecycle_admin_forum_section_path(@section.id)
        assert_equal target.id, topic.reload.forum_section_id
        assert AuditLog.exists?(
          action: "admin.forum_section_topics_migrated",
          resource_id: @section.id
        )
      end

      test "public section routes stop exposing archived sections" do
        Community::ManageSectionLifecycle.call(
          section: @section,
          actor: @admin,
          operation: "archive",
          reason: "Public retirement",
          confirmation: "ARCHIVE #{@section.slug}"
        )

        get forum_sections_path
        assert_response :success
        section_ids = inertia.props.deep_symbolize_keys.fetch(:sections).map { |section| section.fetch(:id) }
        assert_not_includes section_ids, @section.id

        get forum_section_path(@section)
        assert_response :not_found

        post subscription_forum_section_path(@section)
        assert_response :not_found
        patch subscription_forum_section_path(@section), params: { level: "watching" }
        assert_response :not_found
        post mute_forum_section_path(@section)
        assert_response :not_found
        patch mark_all_read_forum_section_path(@section)
        assert_response :not_found
      end

      test "admin permanently deletes only an empty archived section" do
        Community::ManageSectionLifecycle.call(
          section: @section,
          actor: @admin,
          operation: "archive",
          reason: "Duplicate section",
          confirmation: "ARCHIVE #{@section.slug}"
        )

        assert_difference "Community::Section.count", -1 do
          delete admin_forum_section_path(@section.id), params: {
            reason: "Duplicate section",
            confirmation: "DELETE #{@section.slug}"
          }
        end

        assert_redirected_to admin_forum_sections_path
      end

      test "permission is required for lifecycle mutations" do
        delete identity_session_path
        member = create_user
        sign_in_as(member)

        patch archive_admin_forum_section_path(@section.id), params: {
          reason: "Unauthorized",
          confirmation: "ARCHIVE #{@section.slug}"
        }

        assert_redirected_to root_path
        assert_nil @section.reload.archived_at
      end
    end
  end
end
