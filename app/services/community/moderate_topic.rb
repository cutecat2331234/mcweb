# frozen_string_literal: true

module Community
  class ModerateTopic < ApplicationService
    def initialize(user:, topic:, action:, lock_reason: nil, assignee_username: nil)
      @user = user
      @topic = topic
      @action = action.to_s
      @lock_reason = lock_reason.to_s.strip.presence
      @assignee_username = assignee_username.to_s.strip.presence
    end

    def call
      unless Community::SectionModeration.can_moderate_topic_action?(user: @user, topic: @topic, action: @action)
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
          return ServiceResult.failure(error: I18n.t("mcweb.services.errors.bump_cooldown_active", hours: remaining / 3600))
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
        Minecraft::EnqueueBroadcastJob.perform_later(I18n.t("mcweb.forum.announcement_broadcast", title: @topic.title))
      when "remove_global_announcement"
        @topic.update!(global_announcement: false)
      when "unlist"
        @topic.update!(unlisted: true)
      when "list"
        @topic.update!(unlisted: false)
      when "archive"
        @topic.update!(archived_at: Time.current)
      when "unarchive"
        @topic.update!(archived_at: nil)
      when "assign"
        assignee = User.find_by(username: @assignee_username)
        return ServiceResult.failure(error: "assignee_not_found") unless assignee

        @topic.update!(assigned_to: assignee)
        Community::NotifyTopicAssigned.call(topic: @topic, assignee: assignee, actor: @user)
      when "unassign"
        @topic.update!(assigned_to_id: nil)
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
      message = moderation_message
      return if message.blank?

      body = if @lock_reason.present? && @action == "lock"
               I18n.t("mcweb.forum.moderate_actions.lock_with_reason", message: message, reason: @lock_reason)
      else
               message
      end
      Community::CreateSmallActionPost.call(topic: @topic, actor: @user, body: body)
    end

    def moderation_message
      if (match = @action.match(/\Apin_(\d+)\z/))
        return I18n.t("mcweb.forum.moderate_actions.pin_days", days: match[1])
      end

      I18n.t("mcweb.forum.moderate_actions.#{@action}", default: nil)
    end
  end
end
