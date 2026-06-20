# frozen_string_literal: true

module Admin
  module Forum
    class ApprovalsController < BaseController
      before_action :require_approval_staff
      before_action :set_post, only: %i[show approve reject]
      before_action :authorize_post_moderation, only: %i[show approve reject]

      def index
        posts = Community::SectionModeration.pending_posts_scope_for(current_user).limit(100)

        render inertia: "Admin/Generic/Index", props: {
          title: forum_t("approvals.title"),
          columns: [
            admin_column(:author, forum_t("approvals.col_author")),
            admin_column(:topic, forum_t("approvals.col_topic"), link: true),
            admin_column(:section, forum_t("approvals.col_section")),
            admin_column(:excerpt, forum_t("approvals.col_excerpt")),
            admin_column(:time, forum_t("approvals.col_time"))
          ],
          rows: posts.map do |post|
            admin_row(
              author: post.user.username,
              topic: post.topic.title.truncate(60),
              section: post.topic.section.name,
              excerpt: post.body.truncate(80),
              time: l(post.created_at, format: :short),
              url: admin_forum_approval_path(post)
            )
          end
        }
      end

      def show
        post = @post
        attachment_lines = post.attachments.select { |attachment| attachment.file.attached? }.map do |attachment|
          "#{attachment.filename} (#{attachment.human_size})"
        end
        fields = [
          { label: forum_t("approvals.field_author"), value: post.user.username },
          { label: forum_t("approvals.field_topic"), value: post.topic.title },
          { label: forum_t("approvals.field_section"), value: post.topic.section.name },
          { label: forum_t("approvals.field_floor"), value: post.floor_number.to_s },
          { label: forum_t("approvals.field_body"), value: post.body },
          { label: forum_t("approvals.field_submitted_at"), value: l(post.created_at, format: :long) }
        ]
        fields << { label: forum_t("approvals.field_attachments"), value: attachment_lines.join("\n") } if attachment_lines.any?

        render inertia: "Admin/Generic/Show", props: {
          title: forum_t("approvals.show_title"),
          fields: fields,
          backUrl: admin_forum_approvals_path,
          actions: [
            { label: forum_t("approvals.action_approve"), href: approve_admin_forum_approval_path(post), method: "post" },
            { label: forum_t("approvals.action_reject"), href: reject_admin_forum_approval_path(post), method: "post", variant: "destructive" }
          ]
        }
      end

      def approve
        result = Community::ApprovePost.call(actor: current_user, post: @post)
        if result.success?
          redirect_to admin_forum_approvals_path, notice: t("mcweb.flash.post_approved")
        else
          redirect_to admin_forum_approval_path(@post), alert: service_error_message(result)
        end
      end

      def reject
        result = Community::RejectPost.call(actor: current_user, post: @post, reason: params[:reason])
        if result.success?
          redirect_to admin_forum_approvals_path, notice: t("mcweb.flash.post_rejected")
        else
          redirect_to admin_forum_approval_path(@post), alert: service_error_message(result)
        end
      end

      private

      def require_approval_staff
        return if Community::SectionModeration.staff_for_any_section?(current_user)

        redirect_to admin_root_path, alert: t("mcweb.flash.permission_denied")
      end

      def authorize_post_moderation
        return if Community::SectionModeration.can_moderate_topic?(user: current_user, topic: @post.topic)

        redirect_to admin_forum_approvals_path, alert: t("mcweb.flash.cannot_moderate")
      end

      def set_post
        @post = Community::Post.includes(:user, :attachments, topic: :section).find(params[:id])
      end
    end
  end
end
