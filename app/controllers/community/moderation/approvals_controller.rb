# frozen_string_literal: true

module Community
  module Moderation
    class ApprovalsController < ApplicationController
      before_action :require_login
      before_action :require_staff_moderator

      def index
        posts = Community::SectionModeration.pending_posts_scope_for(current_user).limit(100)

        render inertia: "Community/Moderation/Approvals/Index", props: {
          posts: posts.map { |post| serialize_pending_post(post) }
        }
      end

    private

      def require_staff_moderator
        return if Community::SectionModeration.staff_for_any_section?(current_user)

        redirect_to forum_latest_path, alert: t("mcweb.flash.cannot_moderate")
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
          approve_url: approve_forum_post_path(post),
          reject_url: reject_forum_post_path(post)
        }
      end
    end
  end
end
