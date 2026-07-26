# frozen_string_literal: true

module Community
  class ScanPostAttachmentJob < ApplicationJob
    queue_as :maintenance

    def perform(upload_id:)
      upload = Community::Upload.find_by(id: upload_id)
      return unless upload

      result = Community::ScanPostAttachment.call(upload: upload)
      schedule_retry(result)
      result
    end

    private

    def schedule_retry(result)
      return unless result.failure?

      value = result.value.to_h
      return unless value[:retryable] && value[:next_scan_at]

      self.class.set(wait_until: value[:next_scan_at]).perform_later(
        upload_id: value.fetch(:upload).id
      )
    rescue StandardError => error
      Rails.logger.error(
        "[Community::ScanPostAttachmentJob] retry enqueue failed " \
        "upload_id=#{value&.dig(:upload)&.id} error=#{error.class}"
      )
    end
  end
end
