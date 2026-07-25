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
        Community::SectionAccess.view?(section: section, user: api_user)
      end

      def visible_section_ids
        @visible_section_ids ||= Community::SectionAccess.visible_ids(user: api_user)
      end

      # Published, listed, non-redirect topics in sections visible to this key.
      def visible_topics_scope
        Community::ForumAccess.listed_topic_scope(
          relation: Community::Topic
            .where(redirect_to_topic_id: nil),
          user: api_user
        )
      end

      def find_visible_topic!(public_id)
        topic = Community::Topic.find_by!(public_id: public_id)
        visible = topic.status == "published" &&
          Community::ForumAccess.topic_visible?(topic: topic, user: api_user)
        raise ActiveRecord::RecordNotFound unless visible

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
