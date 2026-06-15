# frozen_string_literal: true

module Community
  class CloseOwnTopic < ApplicationService
    def initialize(user:, topic:, action:, lock_reason: nil)
      @user = user
      @topic = topic
      @action = action.to_s
      @lock_reason = lock_reason.to_s.strip.presence
    end

    def call
      unless SiteSetting.get("forum.allow_op_close", "true") == "true"
        return ServiceResult.failure(error: "楼主关闭主题功能未启用。")
      end

      unless @topic.user_id == @user.id
        return ServiceResult.failure(error: "只有主题作者可以关闭或重新打开自己的主题。")
      end

      case @action
      when "close"
        @topic.update!(locked: true, lock_reason: @lock_reason || "作者已关闭此主题。")
        Community::CreateSmallActionPost.call(topic: @topic, actor: @user, body: "作者已关闭此主题。")
      when "reopen"
        @topic.update!(locked: false, lock_reason: nil)
        Community::CreateSmallActionPost.call(topic: @topic, actor: @user, body: "作者已重新打开此主题。")
      else
        return ServiceResult.failure(error: "Unknown action.")
      end

      ServiceResult.success(@topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
