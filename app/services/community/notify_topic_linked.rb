# frozen_string_literal: true

module Community
  # Discourse-style "linked" notification: when a post links to another topic,
  # let that topic's author know their topic was referenced. In-app only.
  class NotifyTopicLinked < ApplicationService
    # Matches internal topic permalinks regardless of host, optional /app prefix,
    # or a trailing #post-N anchor. Captures the topic public_id.
    LINK_RE = %r{/forum/topics/([\w-]+)}i
    MAX_LINKS = 10

    def initialize(post:, author:)
      @post = post
      @author = author
      @source_topic = post.topic
    end

    def call
      # Never broadcast links that live in an unlisted/hidden source topic — it would
      # surface that topic's existence and title to unrelated authors. (Matches the
      # unlisted gate ProcessMentions applies; defensive against future publish paths.)
      return ServiceResult.success if @source_topic.unlisted? || !@source_topic.published?

      public_ids = extract_public_ids
      return ServiceResult.success if public_ids.empty?

      linked_topics = Community::Topic
        .published_listed
        .where(public_id: public_ids)
        .where.not(id: @source_topic.id)
        .includes(:user)
        .first(MAX_LINKS)
      return ServiceResult.success if linked_topics.empty?

      # One recipient (the OP) per linked topic, excluding the author themselves.
      recipients_by_topic = linked_topics.each_with_object({}) do |topic, memo|
        author_id = topic.user_id
        next if author_id == @author.id

        memo[topic] = author_id
      end
      return ServiceResult.success if recipients_by_topic.empty?

      allowed_ids = Community::FilterNotificationRecipients.call(
        actor_id: @author.id,
        recipient_ids: recipients_by_topic.values.uniq,
        topic: @source_topic
      ).value

      recipients_by_topic.each do |linked_topic, recipient_id|
        next unless allowed_ids.include?(recipient_id)
        next unless NotificationPreference.enabled?(linked_topic.user, channel: "in_app", notification_type: "forum.linked")

        Community::InAppNotification.notify(
          user: linked_topic.user,
          notification_type: "forum.linked",
          key: "topic_linked",
          actor: @author.username,
          excerpt: @source_topic.title.truncate(80),
          metadata: {
            topic_id: @source_topic.public_id,
            linked_topic_id: linked_topic.public_id,
            post_id: @post.id,
            path: Community::PostPermalink.path(@source_topic, @post)
          }
        )
      end

      ServiceResult.success
    end

    private

    def extract_public_ids
      @post.body.to_s.scan(LINK_RE).flatten.map(&:to_s).uniq
    end
  end
end
