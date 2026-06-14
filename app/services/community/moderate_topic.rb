# frozen_string_literal: true

module Community
  class ModerateTopic < ApplicationService
    def initialize(user:, topic:, action:)
      @user = user
      @topic = topic
      @action = action.to_s
    end

    def call
      unless @user.permission?("forum.topics.lock")
        return ServiceResult.failure(error: "You are not authorized to moderate this topic.")
      end

      case @action
      when "lock"
        @topic.lock_topic!
      when "unlock"
        @topic.unlock_topic!
      when "pin"
        @topic.update!(pinned: true, pinned_until: nil)
      when /\Apin_(\d+)\z/
        days = Regexp.last_match(1).to_i
        @topic.update!(pinned: true, pinned_until: days.positive? ? days.days.from_now : nil)
      when "unpin"
        @topic.update!(pinned: false, pinned_until: nil)
      when "bump"
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
      else
        return ServiceResult.failure(error: "Unknown moderation action.")
      end

      ServiceResult.success(@topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
