# frozen_string_literal: true

require "set"

module Community
  # Revalidates access to the resources referenced by a notification. Alerts
  # can outlive forum permissions, conversation membership, and subscriptions,
  # so consumers must not trust the title/body captured when they were created.
  class NotificationAccess
    PRIVATE_MESSAGE_TYPE = "forum.private_message"
    POST_REJECTION_TYPE = "forum.post_rejected"
    TAG_TOPIC_TYPE = "forum.tag_topic"
    SAVED_SEARCH_MATCH_TYPE = "forum.saved_search_match"
    BOOKMARK_REMINDER_TYPE = "forum.bookmark_reminder"
    PROFILE_POST_TYPE = "forum.profile_post"
    PROFILE_POST_COMMENT_TYPE = "forum.profile_post_comment"
    REPORT_OUTCOME_TYPE = "forum.report_outcome"
    TAG_SUBSCRIBABLE_TYPE = "Community::Tag"
    CONVERSATION_RESOURCE_TYPES = %w[
      forum.conversation_invite
      forum.private_message
    ].freeze
    POST_RESOURCE_TYPES = %w[
      forum.followed_reply
      forum.here
      forum.linked
      forum.mention
      forum.post_approved
      forum.post_edited
      forum.post_pending
      forum.post_rejected
      forum.post_reply
      forum.quote
      forum.reaction
      forum.topic_reply
      forum.topic_solved
    ].freeze
    TOPIC_RESOURCE_TYPES = %w[
      forum.followed_topic
      forum.poll_closed
      forum.section_topic
      forum.tag_topic
      forum.topic_assigned
      forum.topic_invite
    ].freeze

    def self.filter(notifications:, user:)
      rows = notifications.to_a
      access = new(user: user, notifications: rows)
      rows.select { |notification| access.visible?(notification) }
    end

    def self.visible?(notification:, user:)
      new(user: user, notifications: [ notification ]).visible?(notification)
    end

    def self.private_message_visible?(user:, conversation:, message:)
      return false unless user&.session_eligible? && conversation && message
      return false unless message.persisted?
      return false if message.deleted?
      return false unless message.forum_conversation_id == conversation.id

      conversation.participants.exists?(user_id: user.id)
    end

    # Notification surfaces are aggregate discovery surfaces, not direct-link
    # readers. Preserve the established rule that an unlisted topic is only
    # exposed to its owner or a global moderator, even though a user who already
    # has the URL may still open it directly.
    def self.topic_visible_for_notification?(user:, topic:)
      return false unless user&.session_eligible?
      return false unless Community::ForumAccess.topic_visible?(topic: topic, user: user)
      return true unless topic.unlisted?

      user.present? &&
        (topic.user_id == user.id || user.permission?("forum.topics.lock"))
    end

    def self.post_visible_for_notification?(user:, post:)
      post.present? &&
        topic_visible_for_notification?(user: user, topic: post.topic) &&
        Community::ForumAccess.post_visible?(post: post, user: user)
    end

    # Returns only tags which are still attached to the topic, visible to the
    # recipient, and actively watched by that recipient. Callers must derive
    # display names from this result instead of trusting queued tag names.
    def self.tag_topic_tags(user:, topic:, tag_ids:)
      ids = normalize_ids(tag_ids)
      return [] unless user&.session_eligible? && topic && ids.any?

      subscribed_ids = Community::Subscription
        .where(
          user_id: user.id,
          subscribable_type: TAG_SUBSCRIBABLE_TYPE,
          subscribable_id: ids
        )
        .pluck(:subscribable_id)
        .to_set
      tags_by_id = topic.tags
        .merge(Community::Tag.usable_by(user))
        .where(id: ids)
        .index_by(&:id)

      ids.filter_map { |id| tags_by_id[id] if subscribed_ids.include?(id) }
    end

    def self.normalize_ids(values)
      Array(values).filter_map do |value|
        id = Integer(value, exception: false)
        id if id&.positive?
      end.uniq
    end
    private_class_method :normalize_ids

    def initialize(user:, notifications:)
      @user = user
      @notifications = Array(notifications)
      preload_bookmarks
      preload_topics
      preload_posts
      preload_conversations
      preload_messages
      preload_saved_searches
      preload_profile_posts
      preload_tag_access
      preload_report_outcomes
    end

    def visible?(notification)
      return false unless @user&.session_eligible?
      return false unless notification.user_id == @user.id
      return false unless topic_visible?(notification)
      return false unless post_visible?(notification)
      return false unless conversation_visible?(notification)
      return false unless private_message_visible?(notification)
      return false unless tag_topic_visible?(notification)
      return false unless saved_search_match_visible?(notification)
      return false unless bookmark_reminder_visible?(notification)
      return false unless profile_post_visible?(notification)
      return false unless report_outcome_visible?(notification)

      true
    end

    private

    def preload_bookmarks
      ids = @notifications.filter_map { |notification| bookmark_id(notification) }.uniq
      @bookmarks_by_id = Community::Bookmark
        .where(id: ids, user_id: @user&.id)
        .index_by(&:id)
    end

    def preload_topics
      public_ids = @notifications.flat_map { |notification| topic_public_ids(notification) }.uniq
      bookmark_topic_ids = @bookmarks_by_id.values.map(&:forum_topic_id).uniq
      topics = Community::Topic.with_discarded.where(public_id: public_ids).to_a
      topics.concat(Community::Topic.with_discarded.where(id: bookmark_topic_ids).to_a)
      topics.uniq!(&:id)
      @topics_by_public_id = topics.index_by(&:public_id)
      @topics_by_id = topics.index_by(&:id)
    end

    def preload_conversations
      ids = @notifications.filter_map { |notification| conversation_id(notification) }.uniq
      @conversations_by_id = Community::Conversation.where(id: ids).index_by(&:id)
      @conversation_ids = Community::ConversationParticipant
        .where(user_id: @user&.id, forum_conversation_id: ids)
        .pluck(:forum_conversation_id)
        .to_set
    end

    def preload_posts
      ids = @notifications.filter_map { |notification| post_id(notification) }
      ids.concat(@bookmarks_by_id.values.filter_map(&:forum_post_id))
      ids.uniq!
      @posts_by_id = Community::Post.with_discarded
        .includes(:topic)
        .where(id: ids)
        .index_by(&:id)
    end

    def preload_messages
      ids = @notifications.filter_map { |notification| message_id(notification) }.uniq
      @messages_by_id = Community::Message.with_discarded
        .where(id: ids)
        .index_by(&:id)
    end

    def preload_saved_searches
      ids = @notifications.filter_map { |notification| saved_search_id(notification) }.uniq
      @saved_searches_by_id = Community::SavedSearch
        .where(id: ids, user_id: @user&.id)
        .index_by(&:id)
    end

    def preload_profile_posts
      profile_post_ids = @notifications.filter_map do |notification|
        profile_post_id(notification)
      end
      comment_ids = @notifications.filter_map do |notification|
        profile_post_comment_id(notification)
      end
      comments = Community::ProfilePostComment.with_discarded
        .where(id: comment_ids)
        .to_a
      profile_post_ids.concat(comments.map(&:profile_post_id))
      @profile_posts_by_id = Community::ProfilePost.with_discarded
        .where(id: profile_post_ids.uniq)
        .index_by(&:id)
      @profile_post_comments_by_id = comments.index_by(&:id)
    end

    def preload_tag_access
      tag_notifications = @notifications.select { |notification| tag_topic?(notification) }
      tag_ids = tag_notifications.flat_map { |notification| notification_tag_ids(notification) }.uniq
      @usable_tag_ids = Community::Tag.usable_by(@user).where(id: tag_ids).pluck(:id).to_set
      @subscribed_tag_ids = Community::Subscription
        .where(
          user_id: @user&.id,
          subscribable_type: TAG_SUBSCRIBABLE_TYPE,
          subscribable_id: tag_ids
        )
        .pluck(:subscribable_id)
        .to_set

      topic_ids = tag_notifications.filter_map do |notification|
        @topics_by_public_id[topic_public_id(notification)]&.id
      end
      @topic_tag_pairs = Community::TopicTag
        .where(forum_topic_id: topic_ids, forum_tag_id: tag_ids)
        .pluck(:forum_topic_id, :forum_tag_id)
        .to_set
    end

    def preload_report_outcomes
      notification_ids = @notifications.filter_map do |notification|
        notification.id if notification.notification_type == REPORT_OUTCOME_TYPE
      end
      @report_outcome_deliveries_by_notification_id = Community::ReportOutcomeDelivery
        .includes(:report)
        .where(notification_id: notification_ids)
        .index_by(&:notification_id)
    rescue ActiveRecord::ActiveRecordError
      @report_outcome_deliveries_by_notification_id = {}
    end

    def topic_visible?(notification)
      public_id = topic_public_id(notification)
      if public_id.nil?
        return false if TOPIC_RESOURCE_TYPES.include?(notification.notification_type)

        return true
      end

      self.class.topic_visible_for_notification?(
        user: @user,
        topic: @topics_by_public_id[public_id]
      )
    end

    def conversation_visible?(notification)
      id = conversation_id(notification)
      if id.nil?
        return false if CONVERSATION_RESOURCE_TYPES.include?(notification.notification_type)

        return true
      end

      @conversations_by_id.key?(id) && @conversation_ids.include?(id)
    end

    def private_message_visible?(notification)
      return true unless notification.notification_type == PRIVATE_MESSAGE_TYPE

      conversation = @conversations_by_id[conversation_id(notification)]
      message = @messages_by_id[message_id(notification)]
      self.class.private_message_visible?(
        user: @user,
        conversation: conversation,
        message: message
      )
    end

    def post_visible?(notification)
      id = post_id(notification)
      if id.nil?
        return false if POST_RESOURCE_TYPES.include?(notification.notification_type)

        return true
      end

      post = @posts_by_id[id]
      public_id = topic_public_id(notification)
      return false if public_id && post&.topic&.public_id != public_id
      return post_rejection_visible?(post) if notification.notification_type == POST_REJECTION_TYPE

      self.class.post_visible_for_notification?(user: @user, post: post)
    end

    def post_rejection_visible?(post)
      post.present? &&
        post.persisted? &&
        post.deleted_at.nil? &&
        post.status != "deleted" &&
        post.user_id == @user.id &&
        self.class.topic_visible_for_notification?(user: @user, topic: post.topic)
    end

    def tag_topic_visible?(notification)
      return true unless tag_topic?(notification)

      topic = @topics_by_public_id[topic_public_id(notification)]
      ids = notification_tag_ids(notification)
      return false unless topic && ids.any?

      ids.all? do |tag_id|
        @usable_tag_ids.include?(tag_id) &&
          @subscribed_tag_ids.include?(tag_id) &&
          @topic_tag_pairs.include?([ topic.id, tag_id ])
      end
    end

    def saved_search_match_visible?(notification)
      return true unless notification.notification_type == SAVED_SEARCH_MATCH_TYPE

      search = @saved_searches_by_id[saved_search_id(notification)]
      public_ids = topic_public_ids(notification)
      return false unless search && public_ids.any?

      public_ids.all? do |public_id|
        topic = @topics_by_public_id[public_id]
        Community::ForumAccess.listed_topic_visible?(topic: topic, user: @user)
      end
    end

    def bookmark_reminder_visible?(notification)
      return true unless notification.notification_type == BOOKMARK_REMINDER_TYPE

      bookmark = @bookmarks_by_id[bookmark_id(notification)]
      return false unless bookmark

      topic = @topics_by_id[bookmark.forum_topic_id]
      return false unless self.class.topic_visible_for_notification?(user: @user, topic: topic)
      return true unless bookmark.forum_post_id

      post = @posts_by_id[bookmark.forum_post_id]
      post&.forum_topic_id == topic.id &&
        self.class.post_visible_for_notification?(user: @user, post: post)
    end

    def profile_post_visible?(notification)
      case notification.notification_type
      when PROFILE_POST_TYPE
        visible_profile_post?(@profile_posts_by_id[profile_post_id(notification)])
      when PROFILE_POST_COMMENT_TYPE
        profile_post = @profile_posts_by_id[profile_post_id(notification)]
        comment = @profile_post_comments_by_id[profile_post_comment_id(notification)]
        visible_profile_post?(profile_post) &&
          comment.present? &&
          comment.profile_post_id == profile_post.id &&
          comment.published? &&
          comment.deleted_at.nil?
      else
        true
      end
    end

    def report_outcome_visible?(notification)
      return true unless notification.notification_type == REPORT_OUTCOME_TYPE

      delivery = @report_outcome_deliveries_by_notification_id[notification.id]
      report = delivery&.report
      values = metadata(notification)
      report_id = positive_metadata_id(notification, "report_id")
      outcome = values["public_outcome_code"] || values[:public_outcome_code]
      return false unless report && report_id == report.id
      return false unless report.reporter_id == @user.id
      return false unless report.status.in?(Community::Report::STAFF_FINAL_STATUSES)
      return false unless outcome.to_s == report.public_outcome_code
      return false unless delivery.public_outcome_code == report.public_outcome_code

      notification.destination_path == Rails.application.routes.url_helpers.forum_report_path(report)
    rescue ActiveRecord::ActiveRecordError, ActionController::UrlGenerationError
      false
    end

    def visible_profile_post?(profile_post)
      profile_post.present? &&
        profile_post.published? &&
        profile_post.deleted_at.nil?
    end

    def tag_topic?(notification)
      notification.notification_type == TAG_TOPIC_TYPE
    end

    def metadata(notification)
      values = notification.metadata
      values.is_a?(Hash) ? values : {}
    end

    def topic_public_id(notification)
      values = metadata(notification)
      nested_topic = values["topic"] || values[:topic]
      nested_id = nested_topic["id"] || nested_topic[:id] if nested_topic.is_a?(Hash)
      value = values["topic_id"] || values[:topic_id] || nested_id
      value.to_s.presence
    end

    def topic_public_ids(notification)
      values = metadata(notification)
      ids = Array(values["topic_ids"] || values[:topic_ids]).first(100).filter_map do |value|
        value.to_s.presence
      end
      singular = topic_public_id(notification)
      ids.unshift(singular) if singular
      ids.uniq
    end

    def conversation_id(notification)
      values = metadata(notification)
      value = values["conversation_id"] || values[:conversation_id]
      id = Integer(value, exception: false)
      id if id&.positive?
    end

    def notification_tag_ids(notification)
      values = metadata(notification)
      self.class.send(:normalize_ids, values["tag_ids"] || values[:tag_ids])
    end

    def post_id(notification)
      values = metadata(notification)
      value = values["post_id"] || values[:post_id]
      id = Integer(value, exception: false)
      id if id&.positive?
    end

    def message_id(notification)
      values = metadata(notification)
      value = values["message_id"] || values[:message_id]
      id = Integer(value, exception: false)
      id if id&.positive?
    end

    def bookmark_id(notification)
      positive_metadata_id(notification, "bookmark_id")
    end

    def saved_search_id(notification)
      positive_metadata_id(notification, "search_id")
    end

    def profile_post_id(notification)
      positive_metadata_id(notification, "profile_post_id")
    end

    def profile_post_comment_id(notification)
      positive_metadata_id(notification, "profile_post_comment_id")
    end

    def positive_metadata_id(notification, key)
      values = metadata(notification)
      value = values[key] || values[key.to_sym]
      id = Integer(value, exception: false)
      id if id&.positive?
    end
  end
end
