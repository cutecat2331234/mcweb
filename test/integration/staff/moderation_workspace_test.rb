# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Staff
  class ModerationWorkspaceTest < ActionDispatch::IntegrationTest
    setup do
      suffix = SecureRandom.hex(4)
      category = Community::Category.create!(
        name: "Staff workspace #{suffix}",
        slug: "staff-workspace-#{suffix}"
      )
      @section = Community::Section.create!(
        category: category,
        name: "Staff workspace",
        slug: "staff-workspace-section-#{suffix}",
        position: 0
      )
      @moderator = create_user(username: "staff_moderator_#{suffix}")
      @other_moderator = create_user(username: "staff_assignee_#{suffix}")
      @group_moderator = create_user(username: "staff_group_#{suffix}")
      @author = create_user(username: "staff_subject_#{suffix}")
      Community::SectionModerator.create!(section: @section, user: @moderator)
      Community::SectionModerator.create!(section: @section, user: @other_moderator)
      identity_group = Community::UserGroup.create!(
        name: "Global moderators #{suffix}",
        priority: 50,
        permissions: [ "forum.topics.lock" ]
      )
      Community::GroupMembership.create!(
        user: @group_moderator,
        user_group: identity_group
      )
      @topic = Community::Topic.create!(
        public_id: "topic_#{SecureRandom.alphanumeric(16)}",
        section: @section,
        user: @author,
        title: "Pending staff workspace topic",
        status: "hidden",
        last_posted_at: Time.current,
        last_post_user: @author,
        replies_count: 0
      )
      @post = Community::Post.create!(
        topic: @topic,
        user: @author,
        floor_number: 1,
        body: "Evidence visible to section staff",
        status: "pending_approval"
      )
      sign_in_as(@moderator)
    end

    test "section moderator without admin access can use the staff workspace" do
      refute @moderator.can_access_admin?

      get staff_root_path
      assert_response :success
      assert_includes response.headers["Cache-Control"], "no-store"
      assert_equal "Staff/Dashboard/Index", inertia.component
      assert_operator inertia.props.deep_symbolize_keys.dig(:metrics, :active), :>=, 1

      get staff_moderation_cases_path
      assert_response :success
      assert_equal "Staff/ModerationCases/Index", inertia.component
      props = inertia.props.deep_symbolize_keys
      row = props.fetch(:cases).find { |item| item[:title] == @topic.title }
      assert row
      assert_includes row[:available_actions], "approve"

      get staff_moderation_case_path(row.fetch(:id)), as: :json
      assert_response :success
      detail = JSON.parse(response.body).fetch("case")
      assert_equal @post.body, detail.dig("evidence", "body")
      assert_includes detail.fetch("assignable_staff").pluck("id"), @other_moderator.id
      assert_includes detail.fetch("assignable_staff").pluck("id"), @group_moderator.id
    end

    test "claim assignment and notes use partial JSON endpoints with optimistic locking" do
      moderation_case = sync_case

      post claim_staff_moderation_case_path(moderation_case),
           params: { lock_version: moderation_case.lock_version },
           as: :json
      assert_response :success
      assert_includes response.headers["Cache-Control"], "no-store"
      claimed = JSON.parse(response.body).fetch("case")
      assert_equal @moderator.id, claimed.dig("assignee", "id")

      post assign_staff_moderation_case_path(moderation_case),
           params: {
             lock_version: claimed.fetch("lock_version"),
             assignee_id: @other_moderator.id
           },
           as: :json
      assert_response :success
      assigned = JSON.parse(response.body).fetch("case")
      assert_equal @other_moderator.id, assigned.dig("assignee", "id")

      post notes_staff_moderation_case_path(moderation_case),
           params: {
             lock_version: assigned.fetch("lock_version"),
             body: "Escalated to the section lead."
           },
           as: :json
      assert_response :success
      noted = JSON.parse(response.body).fetch("case")
      assert_equal "Escalated to the section lead.", noted.fetch("notes").last.fetch("body")

      audit_actions = AuditLog.where(actor: @moderator).pluck(:action)
      assert_includes audit_actions, "staff.forum_moderation_case_claim"
      assert_includes audit_actions, "staff.forum_moderation_case_assign"
      assert_includes audit_actions, "staff.forum_moderation_case_note"
    end

    test "ordinary users cannot enter the staff workspace or read its JSON" do
      moderation_case = sync_case
      delete identity_session_path
      regular = create_user
      sign_in_as(regular)

      get staff_root_path
      assert_redirected_to forum_sections_path

      get staff_moderation_case_path(moderation_case), as: :json
      assert_response :redirect
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
