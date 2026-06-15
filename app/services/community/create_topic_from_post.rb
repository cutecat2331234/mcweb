# frozen_string_literal: true

module Community
  class CreateTopicFromPost < ApplicationService
    def initialize(user:, post:, title: nil, body: nil, section: nil, ip_address: nil)
      @user = user
      @post = post
      @source_topic = post.topic
      @title = title.to_s.strip.presence
      @body = body.to_s.strip
      @section = section || @source_topic.section
      @ip_address = ip_address
    end

    def call
      return ServiceResult.failure(error: "Topic not available.") unless PollParticipation.visible?(topic: @source_topic, user: @user)

      unless @section.allowed?(@user, :create_topic)
        return ServiceResult.failure(error: "You are not allowed to create topics in this section.")
      end

      unless @section.trust_allowed?(@user, :create_topic)
        return ServiceResult.failure(error: "Your trust level is too low to create topics in this section.")
      end

      unless @section.writable_by?(@user, :create_topic)
        return ServiceResult.failure(error: "This section is read-only.")
      end

      topic_title = @title || "回复：#{@source_topic.title}".truncate(120)
      opening_body = build_opening_body

      topic = nil
      Community::Topic.transaction do
        topic = Community::Topic.create!(
          public_id: generate_public_id,
          section: @section,
          user: @user,
          title: topic_title,
          status: "published",
          source_post: @post,
          last_posted_at: Time.current,
          last_post_user: @user,
          replies_count: 0
        )

        Community::Post.create!(
          topic: topic,
          user: @user,
          floor_number: 1,
          body: opening_body,
          quoted_post: @post,
          status: "published"
        )

        Community::Subscription.subscribe!(@user, topic)
        Community::ReadState.mark_read!(@user, topic, floor: 1)
      end

      opening_post = topic.posts.first
      Administration::AuditLogger.call(
        actor: @user,
        action: "community.topic_forked_from_post",
        resource: topic,
        ip_address: @ip_address
      )

      Community::ProcessMentions.call(body: opening_body, author: @user, post: opening_post, topic: topic) if opening_post
      Community::NotifySectionTopic.call(topic: topic)
      Community::NotifyPostQuoted.call(post: opening_post, quoter: @user, quoted_post: @post) if opening_post

      ServiceResult.success(topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def build_opening_body
      source_url = Rails.application.routes.url_helpers.forum_topic_path(@source_topic, anchor: "post-#{@post.id}")
      header = "[来自 ##{@post.floor_number} #{@post.user.username} 的回复](#{source_url})"
      quote = @post.body.lines.map { |line| "> #{line.chomp}" }.join("\n")
      parts = [ header, "", quote ]
      parts << "" << @body if @body.present?
      parts.join("\n")
    end

    def generate_public_id
      "topic_#{SecureRandom.alphanumeric(16)}"
    end
  end
end
