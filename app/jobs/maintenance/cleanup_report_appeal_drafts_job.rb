# frozen_string_literal: true

module Maintenance
  class CleanupReportAppealDraftsJob < ApplicationJob
    queue_as :maintenance

    DEFAULT_BATCH_SIZE = 100

    def perform(now: Time.current, limit: DEFAULT_BATCH_SIZE)
      batch_size = Integer(limit, exception: false)
      batch_size = DEFAULT_BATCH_SIZE unless batch_size&.between?(1, 500)

      Community::ReportAppeal.expired_drafts(now).order(:id).limit(batch_size).each do |appeal|
        result = Community::ExpireReportAppealDraft.call(appeal:, now:)
        next if result.success?

        Rails.logger.warn(
          "[CleanupReportAppealDraftsJob] appeal_id=#{appeal.id} code=#{result.code}"
        )
      end

      retry_abandoned_evidence(batch_size)
    end

    private

    def retry_abandoned_evidence(batch_size)
      abandoned_ids = Community::ReportAppeal
        .where(status: "cancelled", submitted_at: nil)
        .select(:id)
      linked_ids = Community::ReportAppealAttachment.select(:secure_evidence_attachment_id)
      SecureEvidence::Attachment
        .where(
          subject_key: "community.report_appeal",
          subject_id: abandoned_ids,
          state: SecureEvidence::Attachment::ACTIVE_STATES
        )
        .where.not(id: linked_ids)
        .order(:id)
        .limit(batch_size)
        .each do |attachment|
          appeal = Community::ReportAppeal.find_by(
            id: attachment.subject_id,
            public_id: attachment.subject_public_id
          )
          next unless appeal

          result = SecureEvidence::DiscardAttachment.call(
            attachment:,
            actor: appeal.appellant
          )
          next if result.success?

          Rails.logger.warn(
            "[CleanupReportAppealDraftsJob] attachment_id=#{attachment.id} code=#{result.code}"
          )
        end
    end
  end
end
