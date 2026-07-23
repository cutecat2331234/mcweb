# frozen_string_literal: true

module Api
  module V1
    # Shared visibility scoping so the API never leaks content the key's user
    # (or an anonymous guest) is not allowed to see. Reuses the same Section
    # visibility rules as the web UI (login-required + view permission).
    module ForumVisibility
      extend ActiveSupport::Concern

      private

      def section_visible?(section)
        return false unless section

        section.visible_to?(api_user) && section.allowed?(api_user, :view)
      end

      def visible_section_ids
        @visible_section_ids ||=
          Community::Section.includes(:category).select { |section| section_visible?(section) }.map(&:id)
      end

      # Published, listed, non-redirect topics in sections visible to this key.
      def visible_topics_scope
        Community::Topic
          .where(forum_section_id: visible_section_ids, status: "published", unlisted: false)
          .where(redirect_to_topic_id: nil)
      end

      def find_visible_topic!(public_id)
        topic = Community::Topic.find_by!(public_id: public_id)
        raise ActiveRecord::RecordNotFound unless topic.status == "published" && section_visible?(topic.section)

        topic
      end

      def visible_posts_scope(topic)
        topic.posts
             .where(status: "published")
             .where.not(post_type: "whisper")
             .order(:floor_number)
      end
    end
  end
end
