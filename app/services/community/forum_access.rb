# frozen_string_literal: true

module Community
  # Canonical read policy for forum topics and posts.
  #
  # The boundary scopes apply only section access. The listed scopes are for
  # aggregate surfaces (activity, profiles, statistics, search, and feeds) and
  # deliberately exclude unlisted/archived topics, non-published posts, and
  # whispers. Direct-link predicates preserve the established web rules for
  # drafts, hidden/archived topics, polls, unlisted topics, pending posts, and
  # moderator-only whispers.
  module ForumAccess
    module_function

    def topic_in_visible_section?(topic:, user:)
      topic.present? &&
        topic.deleted_at.blank? &&
        Community::SectionAccess.view?(section: topic.section, user: user)
    end

    def topic_scope(relation:, user:)
      relation.where(
        forum_section_id: Community::SectionAccess.visible_ids(user: user)
      )
    end

    def post_scope(relation:, user:)
      relation
        .joins(:topic)
        .where(
          forum_topics: {
            forum_section_id: Community::SectionAccess.visible_ids(user: user)
          }
        )
    end

    # Canonical topic scope for any surface that lists or aggregates content.
    # Unlisted topics remain available through topic_visible? by direct URL.
    def listed_topic_scope(relation:, user:)
      topic_scope(
        relation: relation.where(
          status: "published",
          unlisted: false,
          archived_at: nil,
          deleted_at: nil
        ),
        user: user
      )
    end

    # Canonical post scope for aggregate surfaces. Whispers are intentionally
    # absent even for moderators: staff can read them inside an authorized topic
    # via post_visible?, but they must not escape into global/profile feeds.
    def listed_post_scope(relation:, user:)
      post_scope(
        relation: relation
          .where(status: "published", deleted_at: nil)
          .where.not(post_type: "whisper"),
        user: user
      ).where(
        forum_topics: {
          status: "published",
          unlisted: false,
          archived_at: nil,
          deleted_at: nil
        }
      )
    end

    # Direct web topic visibility. Intentionally permits a published unlisted
    # topic by direct URL, matching the previous TopicVisibility behavior.
    def topic_visible?(topic:, user:)
      return false unless topic_in_visible_section?(topic: topic, user: user)
      return false unless Community::PollParticipation.visible?(topic: topic, user: user)

      if topic.archived_at.present?
        return false unless topic_owner_or_moderator?(topic: topic, user: user)
      end

      case topic.status
      when "published"
        true
      when "draft"
        user.present? && topic.user_id == user.id
      when "hidden"
        topic_owner_or_moderator?(topic: topic, user: user)
      else
        false
      end
    end

    # A post can only be read when its topic can be read. This keeps direct-link
    # unlisted topics readable while closing raw-post access to hidden, draft,
    # or archived topics for users who cannot view those topics.
    def topic_readable?(topic:, user:)
      topic_visible?(topic: topic, user: user)
    end

    def listed_topic_visible?(topic:, user:)
      topic_visible?(topic: topic, user: user) &&
        topic.deleted_at.nil? &&
        topic.status == "published" &&
        !topic.unlisted? &&
        topic.archived_at.nil?
    end

    def post_visible?(post:, user:)
      return false unless post
      return false if post.deleted_at.present?

      topic = post.topic
      return false unless topic_readable?(topic: topic, user: user)
      return false unless Community::PollParticipation.visible?(topic: topic, user: user)
      return false if post.whisper? && !whisper_visible?(post: post, user: user)
      return true if post.status != "deleted" && moderator_for_topic?(topic: topic, user: user)
      return true if post.status == "published"

      if post.status == "pending_approval"
        return true if user&.id == post.user_id
        return true if Community::SectionModeration.can_moderate_topic?(user: user, topic: topic)
      end

      false
    end

    def listed_post_visible?(post:, user:)
      post.present? &&
        post.deleted_at.nil? &&
        post.status == "published" &&
        !post.whisper? &&
        listed_topic_visible?(topic: post.topic, user: user)
    end

    # Public API reads intentionally never return whispers or moderation states,
    # even when the key is bound to a moderator. Published unlisted topics remain
    # readable by direct ID, matching the web's direct-link semantics.
    def public_api_post_visible?(post:, user:)
      post.present? &&
        post.deleted_at.nil? &&
        post.status == "published" &&
        !post.whisper? &&
        post.topic&.status == "published" &&
        topic_visible?(topic: post.topic, user: user)
    end

    def whisper_visible?(post:, user:)
      return true if global_moderator?(user)
      return true if Community::SectionModeration.can_moderate_topic?(user: user, topic: post.topic)

      false
    end

    def topic_owner_or_moderator?(topic:, user:)
      user.present? &&
        (
          topic.user_id == user.id ||
          moderator_for_topic?(topic: topic, user: user)
        )
    end
    private_class_method :topic_owner_or_moderator?

    def moderator_for_topic?(topic:, user:)
      global_moderator?(user) ||
        Community::SectionModeration.can_moderate_topic?(user: user, topic: topic)
    end
    private_class_method :moderator_for_topic?

    def global_moderator?(user)
      user&.permission?("forum.topics.lock")
    end
    private_class_method :global_moderator?
  end
end
