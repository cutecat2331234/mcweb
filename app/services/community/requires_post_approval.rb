# frozen_string_literal: true

module Community
  class RequiresPostApproval < ApplicationService
    def initialize(user:, whisper: false)
      @user = user
      @whisper = whisper
    end

    def call
      ServiceResult.success(requires_approval?)
    end

    def self.required_for?(user:, whisper: false)
      new(user: user, whisper: whisper).requires_approval?
    end

    def requires_approval?
      return false if @whisper
      return false if @user.permission?("forum.topics.lock") || @user.permission?("admin.access")

      threshold = SiteSetting.get("forum.require_post_approval_below_tl", "1").to_i
      return false if threshold <= 0

      Community::TrustLevel.level_for(@user) < threshold
    end
  end
end
