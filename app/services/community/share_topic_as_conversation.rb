# frozen_string_literal: true

module Community
  class ShareTopicAsConversation < ApplicationService
    def initialize(sender:, topic:, recipient_username:, message: nil, ip_address: nil)
      @sender = sender
      @topic = topic
      @recipient_username = recipient_username
      @message = message.to_s.strip
      @ip_address = ip_address
    end

    def call
      recipient = User.find_by(username: @recipient_username.to_s.strip)
      return ServiceResult.failure(error: :recipient_not_found) unless recipient
      return ServiceResult.failure(error: :cannot_message_self) if @sender.id == recipient.id
      return ServiceResult.failure(error: :cannot_message_user) if Community::UserBlock.blocked?(@sender, recipient)
      return ServiceResult.failure(error: :new_members_cannot_send_pm) unless Community::TrustLevel.can_send_pm?(@sender)

      unless can_share?
        return ServiceResult.failure(error: :cannot_share_topic)
      end

      body = build_body
      result = Community::CreateConversation.call(
        sender: @sender,
        recipient_username: recipient.username,
        body: body,
        ip_address: @ip_address
      )
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
