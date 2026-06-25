# frozen_string_literal: true

module Community
  class PublishPostSideEffects < ApplicationService
    def initialize(post:, dispatch_webhooks: true)
      @post = post
      @topic = post.topic
      @user = post.user
      @dispatch_webhooks = dispatch_webhooks
    end

    def call
      return ServiceResult.success(skipped: true) if @post.whisper?

      Community::NotifyTopicReply.call(post: @post)
      Community::NotifyFollowedUserReply.call(post: @post)
      Community::ProcessMentions.call(body: @post.body, author: @user, post: @post, topic: @topic)
      Community::ProcessHashtags.call(topic: @topic, body: @post.body, user: @user)
      Community::NotifyTopicLinked.call(post: @post, author: @user)
      if @post.quoted_post
        Community::NotifyPostQuoted.call(post: @post, quoter: @user, quoted_post: @post.quoted_post)
      end

      if @dispatch_webhooks
        if @post.floor_number == 1
          Community::NotifySectionTopic.call(topic: @topic)
          Community::NotifyFollowedUserTopic.call(topic: @topic)
          if @topic.tags.any?
            Community::NotifyTagTopic.call(topic: @topic, tags: @topic.tags)
          end
          Community::DispatchForumEventWebhook.call(event_type: "topic.created", topic: @topic, post: @post)
        else
          Community::DispatchForumEventWebhook.call(event_type: "post.created", topic: @topic, post: @post)
        end
      elsif @post.floor_number == 1
        Community::NotifySectionTopic.call(topic: @topic)
        Community::NotifyFollowedUserTopic.call(topic: @topic)
        if @topic.tags.any?
          Community::NotifyTagTopic.call(topic: @topic, tags: @topic.tags)
        end
      end

      ServiceResult.success
    end
  end
end
