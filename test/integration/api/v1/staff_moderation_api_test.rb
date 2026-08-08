# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class StaffModerationApiTest < ActionDispatch::IntegrationTest
      setup do
        suffix = SecureRandom.hex(4)
        category = Community::Category.create!(
          name: "Staff API #{suffix}",
          slug: "staff-api-#{suffix}"
        )
        @section = Community::Section.create!(
          category: category,
          name: "Staff API",
          slug: "staff-api-section-#{suffix}",
          position: 0
        )
        @moderator = create_user(username: "staff_api_moderator_#{suffix}")
        @author = create_user(username: "staff_api_subject_#{suffix}")
        Community::SectionModerator.create!(section: @section, user: @moderator)
        @topic = Community::Topic.create!(
          public_id: "topic_#{SecureRandom.alphanumeric(16)}",
          section: @section,
          user: @author,
          title: "Pending staff API topic",
          status: "hidden",
          last_posted_at: Time.current,
          last_post_user: @author,
          replies_count: 0
        )
        @post = Community::Post.create!(
          topic: @topic,
          user: @author,
          floor_number: 1,
          body: "Evidence returned through the staff API",
          status: "pending_approval"
        )
        sync_case
        @key, @token = Administration::ApiKey.generate!(
          name: "Staff integration",
          scopes: %w[
            staff.moderation.read
            staff.moderation.claim
            staff.moderation.assign
            staff.moderation.note
            staff.moderation.execute
          ],
          user: @moderator
        )
      end

      test "staff API is self describing and returns only the bound moderator scope" do
        get api_v1_staff_root_path, headers: auth_headers
        assert_response :success
        assert_includes response.headers["Cache-Control"], "no-store"
        root = JSON.parse(response.body)
        assert_equal "staff_moderation", root.fetch("interface")
        assert_equal @moderator.username, root.dig("authenticated_as", "user")
        assert_equal true, root.dig("capabilities", "execute")

        get api_v1_staff_moderation_cases_path, headers: auth_headers
        assert_response :success
        list = JSON.parse(response.body)
        row = list.fetch("data").find { |item| item["title"] == @topic.title }
        assert row
        assert_equal @section.id, row.dig("section", "id")

        get api_v1_staff_moderation_case_path(row.fetch("id")), headers: auth_headers
        assert_response :success
        detail = JSON.parse(response.body).fetch("data")
        assert_equal @post.body, detail.dig("evidence", "body")
      end

      test "claim and note require their fine grained scopes and preserve lock versions" do
        moderation_case = sync_case

        post claim_api_v1_staff_moderation_case_path(moderation_case),
             params: { lock_version: moderation_case.lock_version },
             headers: auth_headers,
             as: :json
        assert_response :success
        claimed = JSON.parse(response.body).fetch("data")
        assert_equal @moderator.id, claimed.dig("assignee", "id")

        post notes_api_v1_staff_moderation_case_path(moderation_case),
             params: {
               lock_version: claimed.fetch("lock_version"),
               body: "Reviewed by an external staff integration."
             },
             headers: auth_headers,
             as: :json
        assert_response :success
        noted = JSON.parse(response.body).fetch("data")
        assert_equal "Reviewed by an external staff integration.",
                     noted.fetch("notes").last.fetch("body")
        assert_includes AuditLog.where(actor: @moderator).pluck(:action),
                        "api_staff.forum_moderation_case_note"

        limited_key, limited_token = Administration::ApiKey.generate!(
          name: "Staff read only",
          scopes: %w[staff.moderation.read],
          user: @moderator
        )
        post claim_api_v1_staff_moderation_case_path(moderation_case),
             params: { lock_version: moderation_case.reload.lock_version },
             headers: auth_headers(limited_token),
             as: :json
        assert_response :forbidden
        error = JSON.parse(response.body)
        assert_equal "insufficient_scope", error.fetch("error")
        assert_equal "staff.moderation.claim", error.fetch("required")
        limited_key.revoke!
      end

      test "staff API rejects unbound keys and users without moderation authority" do
        _unbound, unbound_token = Administration::ApiKey.generate!(
          name: "Unbound staff key",
          scopes: %w[staff.moderation.read]
        )
        get api_v1_staff_root_path, headers: auth_headers(unbound_token)
        assert_response :forbidden
        assert_equal "no_bound_user", JSON.parse(response.body).fetch("error")

        regular = create_user
        _regular_key, regular_token = Administration::ApiKey.generate!(
          name: "Regular user staff key",
          scopes: %w[staff.moderation.read],
          user: regular
        )
        get api_v1_staff_root_path, headers: auth_headers(regular_token)
        assert_response :forbidden
        assert_equal "staff_workspace_forbidden", JSON.parse(response.body).fetch("error")
      end

      private

      def auth_headers(token = @token)
        { "Authorization" => "Bearer #{token}" }
      end

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
