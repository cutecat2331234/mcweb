# frozen_string_literal: true

module Community
  class ShareTopicAsConversation < ApplicationService
    def initialize(sender:, topic:, recipient_username:, message: nil)
      @sender = sender
      @topic = topic
      @recipient_username = recipient_username
      @message = message.to_s.strip
    end

    def call
      recipient = User.find_by(username: @recipient_username.to_s.strip)
      return ServiceResult.failure(error: "Recipient not found.") unless recipient
      return ServiceResult.failure(error: "You cannot message yourself.") if @sender.id == recipient.id
      return ServiceResult.failure(error: "You cannot message this user.") if Community::UserBlock.blocked?(@sender, recipient)
      return ServiceResult.failure(error: "New members cannot send private messages yet.") unless Community::TrustLevel.can_send_pm?(@sender)

      unless can_share?
        return ServiceResult.failure(error: "You are not allowed to share this topic.")
      end

      body = build_body
      result = Community::CreateConversation.call(sender: @sender, recipient_username: recipient.username, body: body)
      return result unless result.success?

      ServiceResult.success(result.value)
    end

    private

    def can_share?
      @sender.id == @topic.user_id ||
        @sender.permission?("forum.topics.lock") ||
        @sender.permission?("forum.conversations.create")
    end

    def build_body
      excerpt = @topic.posts.order(:floor_number).first&.body&.truncate(280)
      lines = []
      lines << @message if @message.present?
      lines << I18n.t("mcweb.forum.share_topic.header", title: @topic.title)
      lines << excerpt if excerpt.present?
      lines << Rails.application.routes.url_helpers.forum_topic_url(@topic, host: default_host)
      lines.join("\n\n")
    end

    def default_host
      ENV.fetch("MCWEB_HOST", "localhost")
    end
  end
end
