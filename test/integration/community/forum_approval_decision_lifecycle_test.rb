# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Community
  class ForumApprovalDecisionLifecycleTest < ActionDispatch::IntegrationTest
    include InertiaRails::Minitest

    setup do
      category = Community::Category.create!(
        name: "Approval lifecycle",
        slug: "approval-lifecycle-#{SecureRandom.hex(4)}"
      )
      @section = Community::Section.create!(
        category: category,
        name: "Approval queue",
        slug: "approval-queue-#{SecureRandom.hex(4)}",
        position: 0
      )
      @moderator = create_user(
        username: "approvalmod#{SecureRandom.hex(3)}",
        account_type: "staff"
      )
      grant_permission(@moderator, "admin.access")
      grant_admin_module(@moderator, "forum")
      Community::SectionModerator.create!(section: @section, user: @moderator)
      @author = create_user(username: "approvalauthor#{SecureRandom.hex(3)}")
      @topic = Community::Topic.create!(
        public_id: "topic_#{SecureRandom.alphanumeric(16)}",
        section: @section,
        user: @author,
        title: "Approval lifecycle topic",
        status: "hidden",
        last_posted_at: Time.current,
        last_post_user: @author,
        replies_count: 0
      )
      @posts = 26.times.map do |index|
        Community::Post.create!(
          topic: @topic,
          user: @author,
          body: "Pending approval #{index + 1}",
          floor_number: index + 1,
          status: "pending_approval"
        )
      end
      sign_in_as(@moderator)
    end

    test "forum and admin queues expose every permission-scoped page" do
      get forum_moderation_approvals_path(page: 2), headers: inertia_headers

      assert_response :success
      assert_equal "private, no-store", response.headers["Cache-Control"]
      assert_equal "Community/Moderation/Approvals/Index", inertia.component
      forum_props = inertia.props.deep_symbolize_keys
      assert_equal(
        { page: 2, pages: 2, count: 26 },
        forum_props.fetch(:pagination).slice(:page, :pages, :count)
      )
      assert_equal Community::RejectPost::REASON_MAX_LENGTH, forum_props.fetch(:reason_max_length)
      assert_equal [ @posts.first.id ], forum_props.fetch(:posts).pluck(:id)
      assert_includes forum_props.dig(:posts, 0, :approve_url), "approval_queue_page=2"
      assert_includes forum_props.dig(:posts, 0, :reject_url), "approval_queue_page=2"

      get admin_forum_approvals_path(page: 2), headers: inertia_headers

      assert_response :success
      assert_equal "Admin/Generic/Index", inertia.component
      admin_props = inertia.props.deep_symbolize_keys
      assert_equal(
        { page: 2, pages: 2, count: 26 },
        admin_props.fetch(:pagination).slice(:page, :pages, :count)
      )
      assert_equal 1, admin_props.fetch(:rows).size
      assert_includes admin_props.dig(:rows, 0, :url), "approval_queue_page=2"
    end

    test "topic moderation action receives the shared rejection contract" do
      get forum_topic_path(@topic), headers: inertia_headers

      assert_response :success
      assert_equal "Community/Topics/Show", inertia.component
      pending_post = inertia.props.deep_symbolize_keys
        .fetch(:posts)
        .find { |item| item.fetch(:id) == @posts.first.id }
      assert pending_post.fetch(:reject_url).present?
      assert_equal(
        Community::RejectPost::REASON_MAX_LENGTH,
        pending_post.fetch(:rejection_reason_max_length)
      )
    end

    test "admin detail and validation keep the canonical queue page" do
      pending_post = @posts.first

      get admin_forum_approval_path(pending_post, approval_queue_page: 2), headers: inertia_headers

      assert_response :success
      assert_equal "Admin/Forum/Approvals/Show", inertia.component
      props = inertia.props.deep_symbolize_keys
      assert_equal admin_forum_approvals_path(page: 2), props.fetch(:backUrl)
      assert_includes props.fetch(:approveUrl), "approval_queue_page=2"
      assert_includes props.fetch(:rejectUrl), "approval_queue_page=2"
      assert_equal Community::RejectPost::REASON_MAX_LENGTH, props.fetch(:reasonMaxLength)

      post reject_admin_forum_approval_path(pending_post), params: {
        approval_queue_page: 2,
        reason: "  "
      }

      assert_redirected_to admin_forum_approval_path(pending_post, approval_queue_page: 2)
      assert_equal "pending_approval", pending_post.reload.status
    end

    test "a decision that empties the last page recovers to the new last page" do
      pending_post = @posts.first

      post reject_forum_post_path(pending_post), params: {
        approval_queue_page: 2,
        reason: "Duplicate submission"
      }

      assert_redirected_to forum_moderation_approvals_path(page: 2)
      assert_equal "hidden", pending_post.reload.status

      get forum_moderation_approvals_path(page: 2)

      assert_redirected_to forum_moderation_approvals_path(page: 1)

      get admin_forum_approvals_path(page: 2)

      assert_redirected_to admin_forum_approvals_path(page: 1)
    end

    test "revoked moderation access fails closed to a readable destination" do
      pending_post = @posts.first
      Community::SectionModerator.where(section: @section, user: @moderator).delete_all

      post reject_forum_post_path(pending_post), params: { reason: "No longer authorized" }

      assert_redirected_to forum_latest_path
      assert_equal "pending_approval", pending_post.reload.status
      assert_equal 0, Notification.where(
        user: @author,
        notification_type: "forum.post_rejected"
      ).count
    end

    private

    def inertia_headers
      {
        "X-Inertia" => "true",
        "X-Inertia-Version" => InertiaRails.configuration.version
      }
    end
  end
end
