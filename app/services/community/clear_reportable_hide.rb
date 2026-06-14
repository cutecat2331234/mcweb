# frozen_string_literal: true

module Community
  class ClearReportableHide < ApplicationService
    def initialize(reportable:)
      @reportable = reportable
    end

    def call
      return ServiceResult.success(skipped: true) unless @reportable

      pending = Community::Report.pending_review.where(reportable: @reportable).exists?
      return ServiceResult.success(skipped: true) if pending

      case @reportable
      when Community::Post
        @reportable.update!(status: :published) if @reportable.status == "hidden" && @reportable.deleted_at.blank?
      when Community::Topic
        @reportable.update!(status: :published) if @reportable.status == "hidden"
      end

      ServiceResult.success
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
