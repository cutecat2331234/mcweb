# frozen_string_literal: true

module Api
  module V1
    # Shared, safe JSON serialization for the public API. Only exposes public
    # fields; never leaks emails, tokens, staff notices, or moderation internals.
    module Serialization
      extend ActiveSupport::Concern

      private

      def serialize_category(category)
        {
          id: category.slug,
          name: category.name,
          description: category.try(:description)
        }
      end

      def serialize_section(section)
        {
          id: section.slug,
          name: section.name,
          description: section.try(:description),
          category_id: section.category&.slug,
          parent_id: section.parent&.slug,
          topics_count: Community::ForumAccess.listed_topic_scope(
            relation: section.topics,
            user: api_user
          ).count
        }
      end

      def serialize_topic(topic, include_section: true)
        data = {
          id: topic.public_id,
          title: topic.title,
          prefix: topic.prefix,
          replies_count: topic.replies_count,
          views_count: topic.views_count,
          pinned: topic.pinned,
          locked: topic.locked,
          solved: topic.solved_post_id.present?,
          wiki: topic.wiki,
          author: serialize_user_ref(topic.user),
          created_at: topic.created_at&.iso8601,
          last_posted_at: topic.last_posted_at&.iso8601,
          tags: topic.tags.map { |t| { id: t.slug, name: t.name } },
          custom_fields: Community::SerializeTopicFields.for_display(
            topic: topic,
            definitions: serialized_topic_field_definitions
          )
        }
        data[:section_id] = topic.section&.slug if include_section
        data
      end

      def serialize_post(post)
        {
          id: post.id,
          topic_id: post.topic&.public_id,
          floor_number: post.floor_number,
          body: post.body,
          author: serialize_user_ref(post.user),
          wiki: post.wiki,
          created_at: post.created_at&.iso8601,
          edited_at: post.edited_at&.iso8601
        }
      end

      def serialize_user_ref(user)
        return nil unless user

        {
          id: user.public_id,
          username: user.username,
          display_name: user.display_name
        }
      end

      def serialize_user(user)
        serialize_user_ref(user).merge(
          forum_title: user.forum_title,
          forum_posts_count: serialized_forum_post_count(user),
          bio: user.bio,
          created_at: user.created_at&.iso8601
        )
      end

      def preload_serialized_forum_post_counts(users)
        user_ids = users.map(&:id)
        @serialized_forum_post_counts = serialized_forum_posts_scope
          .where(user_id: user_ids)
          .group(:user_id)
          .count
      end

      def serialized_forum_post_count(user)
        if defined?(@serialized_forum_post_counts)
          return @serialized_forum_post_counts[user.id].to_i
        end

        serialized_forum_posts_scope.where(user: user).count
      end

      def serialized_forum_posts_scope
        @serialized_forum_posts_scope ||= Community::ForumAccess.listed_post_scope(
          relation: Community::Post.all,
          user: api_user
        )
      end

      def serialized_topic_field_definitions
        @serialized_topic_field_definitions ||= Community::TopicFieldDefinition.active.ordered.to_a
      end
    end
  end
end
