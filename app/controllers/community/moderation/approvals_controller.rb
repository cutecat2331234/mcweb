# frozen_string_literal: true

module Community
  module Moderation
    class ApprovalsController < ApplicationController
      include PrivateNoStoreResponse

      PAGE_SIZE = 25

      before_action :require_login
      before_action :require_staff_moderator

      def index
        @pagy, posts = pagy(
          :offset,
          Community::SectionModeration.pending_posts_scope_for(current_user),
          limit: PAGE_SIZE,
          page: requested_queue_page
        )
        return redirect_to(forum_moderation_approvals_path(page: @pagy.pages)) if @pagy.page > @pagy.pages

        render inertia: "Community/Moderation/Approvals/Index", props: {
          posts: posts.map { |post| serialize_pending_post(post) },
          pagination: pagy_props(@pagy),
          reason_max_length: Community::RejectPost::REASON_MAX_LENGTH
        }
      end

    private

      def require_staff_moderator
        return if Community::SectionModeration.staff_for_any_section?(current_user)

        redirect_to forum_latest_path, alert: t("mcweb.flash.cannot_moderate")
      end

      def requested_queue_page
        page = Integer(params[:page], exception: false).to_i
        page.positive? ? page : 1
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
          approve_url: approve_forum_post_path(post, approval_queue_page: @pagy.page),
          reject_url: reject_forum_post_path(post, approval_queue_page: @pagy.page)
        }
      end
    end
  end
end
