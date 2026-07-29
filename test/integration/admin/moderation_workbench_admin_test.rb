# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  module Forum
    class ModerationWorkbenchAdminTest < ActionDispatch::IntegrationTest
      setup do
        suffix = SecureRandom.hex(4)
        category = Community::Category.create!(
          name: "Admin workbench #{suffix}",
          slug: "admin-workbench-#{suffix}"
        )
        @section = Community::Section.create!(
          category: category,
          name: "Admin workbench",
          slug: "admin-workbench-section-#{suffix}",
          position: 0
        )
        @admin = create_user(
          username: "workbench_admin_#{suffix}",
          account_type: "admin"
        )
        @author = create_user(username: "workbench_subject_#{suffix}")
        grant_permission(@admin, "admin.access")
        Community::SectionModerator.create!(section: @section, user: @admin)
        @topic = Community::Topic.create!(
          public_id: "topic_#{SecureRandom.alphanumeric(16)}",
          section: @section,
          user: @author,
          title: "Pending admin workbench topic",
          status: "hidden",
          last_posted_at: Time.current,
          last_post_user: @author,
          replies_count: 0
        )
        @post = Community::Post.create!(
          topic: @topic,
          user: @author,
          floor_number: 1,
          body: "Pending evidence for the workbench",
          status: "pending_approval"
        )
        sign_in_as(@admin)
      end

      test "authorized moderator receives no-store inertia queue and cropped JSON detail" do
        get "/admin/forum/moderation-workbench"

        assert_response :success
        assert_equal "no-store", response.headers["Cache-Control"]
        assert_equal "Admin/Forum/ModerationWorkbench/Index", inertia.component
        props = inertia.props.deep_symbolize_keys
        row = props.fetch(:cases).find do |item|
          item[:source_kind] == "pending_topic" && item[:title] == @topic.title
        end
        assert row
        assert_equal @section.id, row.dig(:section, :id)
        assert_includes row[:available_actions], "approve"

        get "/admin/forum/moderation-workbench/#{row.fetch(:id)}", as: :json

        assert_response :success
        assert_equal "no-store", response.headers["Cache-Control"]
        detail = JSON.parse(response.body).fetch("case")
        assert_equal row.fetch(:id), detail.fetch("id")
        assert_equal false, detail.dig("evidence", "restricted")
        assert_equal "post", detail.dig("evidence", "type")
        assert_equal @post.body, detail.dig("evidence", "body")
      end

      test "claim and note JSON endpoints enforce lock versions and never cache responses" do
        moderation_case = sync_case

        post "/admin/forum/moderation-workbench/#{moderation_case.id}/claim",
             params: { lock_version: moderation_case.lock_version },
             as: :json

        assert_response :success
        assert_equal "no-store", response.headers["Cache-Control"]
        claimed = JSON.parse(response.body).fetch("case")
        assert_equal "claimed", claimed.fetch("status")
        assert_equal @admin.id, claimed.dig("assignee", "id")

        post "/admin/forum/moderation-workbench/#{moderation_case.id}/notes",
             params: {
               lock_version: claimed.fetch("lock_version"),
               body: "Reviewed from the integrated workbench."
             },
             as: :json

        assert_response :success
        assert_equal "no-store", response.headers["Cache-Control"]
        noted = JSON.parse(response.body).fetch("case")
        assert_equal "Reviewed from the integrated workbench.",
                     noted.fetch("notes").last.fetch("body")

        post "/admin/forum/moderation-workbench/#{moderation_case.id}/notes",
             params: {
               lock_version: claimed.fetch("lock_version"),
               body: "A stale duplicate"
             },
             as: :json

        assert_response :conflict
        assert_equal "no-store", response.headers["Cache-Control"]
        assert_equal "moderation_case_conflict", JSON.parse(response.body).fetch("error")
      end

      test "authorize and execute endpoints return preview challenge and per-item JSON results" do
        moderation_case = sync_case
        request_id = SecureRandom.uuid
        reason = "The content follows the published section rules."

        post "/admin/forum/moderation-workbench/authorize-action",
             params: {
               case_ids: [ moderation_case.id ],
               action: "approve",
               request_id: request_id,
               reason: reason,
               attributes: {}
             },
             as: :json

        assert_response :success
        assert_equal "no-store", response.headers["Cache-Control"]
        authorization = JSON.parse(response.body)
        assert_equal request_id, authorization.fetch("request_id")
        assert_equal true, authorization.dig("preview", 0, "eligible")
        assert_match(/\ACONFIRM APPROVE /, authorization.fetch("typed_confirmation"))

        post "/admin/forum/moderation-workbench/execute-action",
             params: {
               case_ids: [ moderation_case.id ],
               action: "approve",
               request_id: request_id,
               reason: reason,
               attributes: {},
               authorization_token: authorization.fetch("authorization_token"),
               typed_confirmation: authorization.fetch("typed_confirmation")
             },
             as: :json

        assert_response :success
        assert_equal "no-store", response.headers["Cache-Control"]
        result = JSON.parse(response.body)
        assert_equal false, result.fetch("replayed")
        assert_equal "success", result.dig("results", 0, "status")
        assert_equal "published", @post.reload.status
        assert_equal "actioned", moderation_case.reload.status
      end

      test "admin without moderation or evidence capability is redirected and cannot read JSON" do
        delete identity_session_path
        limited = create_user(account_type: "admin")
        grant_permission(limited, "admin.access")
        sign_in_as(limited)
        moderation_case = sync_case

        get "/admin/forum/moderation-workbench"
        assert_redirected_to admin_root_path

        get "/admin/forum/moderation-workbench/#{moderation_case.id}", as: :json
        assert_response :redirect
        assert_not_equal 200, response.status
        refute_includes response.body, @post.body
      end

      private

      def sync_case
        result = Community::ModerationWorkbench::SyncCases.call
        assert_predicate result, :success?, result.error
        Community::ModerationCase.find_by!(
          source_type: "Community::Post",
          source_id: @post.id
        )
      end
    end
  end
end
