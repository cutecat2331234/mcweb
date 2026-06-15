# frozen_string_literal: true

module Community
  class DismissGlobalAnnouncement < ApplicationService
    def initialize(user:, topic_public_id:)
      @user = user
      @topic_public_id = topic_public_id.to_s.strip
    end

    def call
      return ServiceResult.failure(error: "Topic id required.") if @topic_public_id.blank?

      ids = Array(@user.dismissed_global_announcement_ids).map(&:to_s)
      return ServiceResult.success(dismissed: ids) if ids.include?(@topic_public_id)

      @user.update!(dismissed_global_announcement_ids: (ids + [ @topic_public_id ]).uniq.last(50))
      ServiceResult.success(dismissed: @user.dismissed_global_announcement_ids)
    end
  end
end
