# frozen_string_literal: true

module Staff
  module Forum
    class ApprovalsController < Staff::BaseController
      PAGE_SIZE = 25

      before_action :require_forum_moderator!
      before_action :set_post, only: %i[approve reject]

      def index
        @pagy, posts = pagy(
          :offset,
          Community::SectionModeration.pending_posts_scope_for(current_user),
          limit: PAGE_SIZE,
          page: requested_queue_page
        )
        if @pagy.page > @pagy.pages
          redirect_to staff_forum_approvals_path(page: @pagy.pages)
          return
        end

        render inertia: "Staff/Forum/Approvals/Index", props: {
          posts: posts.map { |post| serialize_pending_post(post) },
          pagination: pagy_props(@pagy),
          reason_max_length: Community::RejectPost::REASON_MAX_LENGTH
        }
      end

      def approve
        result = Community::ApprovePost.call(actor: current_user, post: @post)
        redirect_to queue_return_path,
          **result_flash(result, success_key: "mcweb.flash.post_approved")
      end

      def reject
        result = Community::RejectPost.call(
          actor: current_user,
          post: @post,
          reason: params[:reason]
        )
        redirect_to queue_return_path,
          **result_flash(result, success_key: "mcweb.flash.post_rejected")
      end

      private

      def require_forum_moderator!
        return if Community::SectionModeration.staff_for_any_section?(current_user)

        redirect_to staff_root_path, alert: t("mcweb.flash.cannot_moderate")
      end

      def set_post
        @post = Community::Post.find(params[:id])
      end

      def requested_queue_page
        page = Integer(params[:page], exception: false).to_i
        page.positive? ? page : 1
      end

      def queue_return_path
        page = Integer(params[:approval_queue_page], exception: false).to_i
        staff_forum_approvals_path(page: page.positive? ? page : nil)
      end

      def result_flash(result, success_key:)
        if result.success?
          { notice: t(success_key) }
        else
          { alert: service_error_message(result) }
        end
      end

      def serialize_pending_post(post)
        {
          id: post.id,
          author: post.user.username,
          topic_title: post.topic.title,
          topic_url: forum_topic_path(post.topic, anchor: "post-#{post.id}"),
          section_name: post.topic.section.name,
          excerpt: post.body.truncate(160),
          created_at: l(post.created_at, format: :short),
          attachments: post.attachments.select { |attachment| attachment.file.attached? }.map do |attachment|
            {
              filename: attachment.filename,
              human_size: attachment.human_size,
              download_url: forum_attachment_path(attachment)
            }
          end,
          approve_url: approve_staff_forum_approval_path(
            post,
            approval_queue_page: @pagy.page
          ),
          reject_url: reject_staff_forum_approval_path(
            post,
            approval_queue_page: @pagy.page
          )
        }
      end
    end
  end
end
