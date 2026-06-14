# frozen_string_literal: true

module Community
  class ModerateTopic < ApplicationService
    SMALL_ACTION_MESSAGES = {
      "lock" => "此主题已锁定。",
      "unlock" => "此主题已解锁。",
      "pin" => "此主题已置顶。",
      "unpin" => "此主题已取消置顶。",
      "hide" => "此主题已隐藏。",
      "unhide" => "此主题已恢复显示。",
      "feature" => "此主题已设为精选。",
      "unfeature" => "此主题已取消精选。",
      "enable_wiki" => "此主题已开启 Wiki 模式。",
      "disable_wiki" => "此主题已关闭 Wiki 模式。",
      "global_announcement" => "此主题已设为全站公告。",
      "remove_global_announcement" => "此主题已取消全站公告。"
    }.freeze

    def initialize(user:, topic:, action:, lock_reason: nil)
      @user = user
      @topic = topic
      @action = action.to_s
      @lock_reason = lock_reason.to_s.strip.presence
    end

    def call
      unless @user.permission?("forum.topics.lock")
        return ServiceResult.failure(error: "You are not authorized to moderate this topic.")
      end

      case @action
      when "lock"
        @topic.update!(locked: true, lock_reason: @lock_reason)
      when "unlock"
        @topic.update!(locked: false, lock_reason: nil)
      when "pin"
        @topic.update!(pinned: true, pinned_until: nil)
      when /\Apin_(\d+)\z/
        days = Regexp.last_match(1).to_i
        @topic.update!(pinned: true, pinned_until: days.positive? ? days.days.from_now : nil)
      when "unpin"
        @topic.update!(pinned: false, pinned_until: nil)
      when "bump"
        cooldown_hours = SiteSetting.get("forum.bump_cooldown_hours", "24").to_i
        if cooldown_hours.positive? && @topic.bumped_at && @topic.bumped_at > cooldown_hours.hours.ago
          remaining = ((@topic.bumped_at + cooldown_hours.hours) - Time.current).to_i
          return ServiceResult.failure(error: "提升冷却中，请 #{remaining / 3600} 小时后再试。")
        end
        @topic.update!(bumped_at: Time.current, last_posted_at: Time.current)
      when "hide"
        @topic.update!(status: "hidden")
      when "unhide"
        @topic.update!(status: "published")
      when "feature"
        @topic.update!(featured: true)
      when "unfeature"
        @topic.update!(featured: false)
      when "enable_wiki"
        @topic.update!(wiki: true)
      when "disable_wiki"
        @topic.update!(wiki: false)
      when "global_announcement"
        @topic.update!(global_announcement: true)
      when "remove_global_announcement"
        @topic.update!(global_announcement: false)
      else
        return ServiceResult.failure(error: "Unknown moderation action.")
      end

      record_small_action! unless @action == "bump"

      ServiceResult.success(@topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def record_small_action!
      message = SMALL_ACTION_MESSAGES[@action]
      message = "此主题已置顶 #{Regexp.last_match(1)} 天。" if @action.match?(/\Apin_(\d+)\z/)
      return if message.blank?

      body = @lock_reason.present? && @action == "lock" ? "#{message} 原因：#{@lock_reason}" : message
      Community::CreateSmallActionPost.call(topic: @topic, actor: @user, body: body)
    end
  end
end
