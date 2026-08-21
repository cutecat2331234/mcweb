# frozen_string_literal: true

module Community
  # Explicitly hides reported content when a moderator agrees with a flag
  # (Discourse "agree and hide"), independent of the auto-hide threshold.
  class HideReportable < ApplicationService
    def initialize(reportable:)
      @reportable = reportable
    end

    def call
      return ServiceResult.success(hidden: false, skipped: "missing_reportable") unless @reportable

      hidden = case @reportable
      when Community::Post
        if @reportable.status != "hidden" && @reportable.deleted_at.blank?
          @reportable.update!(status: :hidden)
          Community::SyncTopicLastPost.call(topic: @reportable.topic)
        end
        @reportable.status == "hidden"
      when Community::Topic
        @reportable.update!(status: :hidden) if @reportable.status != "hidden"
        @reportable.status == "hidden"
      when Community::ProfilePost
        @reportable.update!(status: :hidden) if @reportable.status != "hidden" && @reportable.deleted_at.blank?
        @reportable.status == "hidden"
      else
        false
      end

      if hidden
        ServiceResult.success(hidden: true)
      else
        ServiceResult.success(hidden: false, skipped: "unsupported_or_retained_reportable")
      end
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
