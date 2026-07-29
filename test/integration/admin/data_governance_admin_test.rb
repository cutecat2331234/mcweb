# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  module System
    class DataGovernanceAdminTest < ActionDispatch::IntegrationTest
      setup do
        @admin = create_user(account_type: "admin")
        @author = create_user
        grant_permission(@admin, "admin.access")
        %w[
          data_governance.read
          data_governance.policies.manage
          data_governance.holds.manage
          data_governance.content.delete
          data_governance.content.restore
          data_governance.content.purge
        ].each { |key| grant_permission(@admin, key) }

        suffix = SecureRandom.hex(4)
        category = Community::Category.create!(
          name: "Governance admin #{suffix}",
          slug: "governance-admin-#{suffix}"
        )
        section = Community::Section.create!(
          category:,
          name: "Governance admin",
          slug: "governance-admin-section-#{suffix}",
          position: 0
        )
        @topic = Community::Topic.create!(
          public_id: "topic_#{SecureRandom.alphanumeric(16)}",
          section:,
          user: @author,
          title: "Governance admin topic",
          status: "published",
          last_posted_at: Time.current,
          last_post_user: @author,
          replies_count: 0
        )
        @post = Community::Post.create!(
          topic: @topic,
          user: @author,
          floor_number: 1,
          body: "Governance admin post",
          status: "published"
        )
        DataGovernance::RetentionPolicy.ensure_defaults!
        sign_in_as(@admin)
      end

      test "index returns the Arco workbench contract without cacheable sensitive state" do
        get admin_system_data_governance_path

        assert_response :success
        assert_equal "private, no-store", response.headers["Cache-Control"]
        assert_equal "Admin/System/DataGovernance/Index", inertia.component
        props = inertia.props.deep_symbolize_keys
        assert props.fetch(:policies).any? { |policy| policy[:resourceType] == "Community::Post" }
        assert_equal true, props.dig(:permissions, :managePolicies)
        assert_includes props.fetch(:resourceTypes).pluck(:value), "Community::Topic"
        assert_equal admin_system_data_governance_soft_delete_path,
                     props.dig(:paths, :softDelete)
      end

      test "JSON lifecycle and hold endpoints stay in-app and return audited state" do
        post admin_system_data_governance_soft_delete_path,
             params: {
               target_type: "Community::Post",
               target_reference: @post.id,
               reason: "Remove the post while retaining recovery."
             },
             as: :json

        assert_response :success
        assert_equal "private, no-store", response.headers["Cache-Control"]
        record = JSON.parse(response.body).fetch("record")
        assert_equal "soft_deleted", record.fetch("status")
        assert_predicate @post.reload, :soft_deleted?

        post admin_system_data_governance_holds_path,
             params: {
               target_type: "Community::Post",
               target_reference: @post.id,
               reason: "Preserve pending case evidence.",
               policy_reference: "CASE-ADMIN-1"
             },
             as: :json

        assert_response :success
        hold = JSON.parse(response.body).fetch("hold")
        assert_equal true, hold.fetch("effective")

        patch admin_system_data_governance_release_hold_path(hold.fetch("id")),
              params: { reason: "The case is closed." },
              as: :json
        assert_response :success

        patch admin_system_data_governance_restore_path(record.fetch("id")),
              params: { reason: "Restore requested by moderator." },
              as: :json
        assert_response :success
        assert_equal "restored", JSON.parse(response.body).dig("record", "status")
        refute_predicate @post.reload, :soft_deleted?
      end

      test "each mutating endpoint enforces its granular permission" do
        delete identity_session_path
        limited = create_user(account_type: "admin")
        grant_permission(limited, "admin.access")
        grant_permission(limited, "data_governance.read")
        sign_in_as(limited)

        get admin_system_data_governance_path
        assert_response :success

        post admin_system_data_governance_soft_delete_path,
             params: {
               target_type: "Community::Post",
               target_reference: @post.id,
               reason: "This must be denied."
             },
             as: :json

        assert_response :redirect
        refute_predicate @post.reload, :soft_deleted?
      end

      test "manual purge returns blocker codes and succeeds only after the hold clears" do
        policy = DataGovernance::RetentionPolicy.find_by!(resource_type: "Community::Post")
        patch admin_system_data_governance_policy_path(policy),
              params: {
                retention_days: 0,
                user_deletable: true,
                moderator_restorable: true,
                legal_hold_supported: true,
                notes: "Immediate eligibility still requires evidence checks.",
                reason: "Exercise the permanent-cleanup boundary."
              },
              as: :json
        assert_response :success

        post admin_system_data_governance_soft_delete_path,
             params: {
               target_type: "Community::Post",
               target_reference: @post.id,
               reason: "Prepare content for cleanup."
             },
             as: :json
        record_id = JSON.parse(response.body).dig("record", "id")

        post admin_system_data_governance_holds_path,
             params: {
               target_type: "Community::Topic",
               target_reference: @topic.public_id,
               reason: "Parent-topic evidence is still under review."
             },
             as: :json
        hold_id = JSON.parse(response.body).dig("hold", "id")

        delete admin_system_data_governance_purge_path(record_id),
               params: { reason: "Try cleanup while evidence is held." },
               as: :json

        assert_response :unprocessable_entity
        blocked = JSON.parse(response.body)
        assert_equal "content_purge_blocked", blocked.fetch("error")
        assert_includes blocked.fetch("blockers"), "legal_hold"
        assert Community::Post.with_discarded.exists?(@post.id)

        patch admin_system_data_governance_release_hold_path(hold_id),
              params: { reason: "The evidence review is complete." },
              as: :json
        assert_response :success

        delete admin_system_data_governance_purge_path(record_id),
               params: { reason: "Retention and evidence checks are clear." },
               as: :json

        assert_response :success
        assert_equal "purged", JSON.parse(response.body).dig("record", "status")
        refute Community::Post.with_discarded.exists?(@post.id)
      end
    end
  end
end
