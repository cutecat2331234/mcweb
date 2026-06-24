# frozen_string_literal: true

module Community
  # Explicitly hides reported content when a moderator agrees with a flag
  # (Discourse "agree and hide"), independent of the auto-hide threshold.
  class HideReportable < ApplicationService
    def initialize(reportable:)
      @reportable = reportable
    end

    def call
      return ServiceResult.success(skipped: true) unless @reportable

      case @reportable
      when Community::Post
        if @reportable.status != "hidden" && @reportable.deleted_at.blank?
          @reportable.update!(status: :hidden)
          Community::SyncTopicLastPost.call(topic: @reportable.topic)
        end
      when Community::Topic
        @reportable.update!(status: :hidden) if @reportable.status != "hidden"
      when Community::ProfilePost
        @reportable.update!(status: :hidden) if @reportable.status != "hidden" && @reportable.deleted_at.blank?
      end

      ServiceResult.success(hidden: true)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
