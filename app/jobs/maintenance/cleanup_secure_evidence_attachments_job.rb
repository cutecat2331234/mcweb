# frozen_string_literal: true

module Maintenance
  class CleanupSecureEvidenceAttachmentsJob < ApplicationJob
    queue_as :maintenance

    DEFAULT_BATCH_SIZE = 200

    def perform(now: Time.current, limit: DEFAULT_BATCH_SIZE)
      batch_size = Integer(limit, exception: false)
      batch_size = DEFAULT_BATCH_SIZE unless batch_size&.between?(1, 1_000)

      SecureEvidence::Attachment.retention_due(now).order(:id).limit(batch_size).each do |attachment|
        SecureEvidence::PurgeAttachment.call(attachment:, now:)
      end
    end
  end
end
