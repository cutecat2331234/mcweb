# frozen_string_literal: true

module Maintenance
  class ScanForumAttachmentsJob < ApplicationJob
    queue_as :maintenance

    DEFAULT_BATCH_SIZE = 200

    def perform(now: Time.current, limit: nil)
      batch_size = normalized_batch_size(limit)
      adopt_unmanaged_attachments(now, batch_size)

      Community::Upload.scan_due(now).order(:id).limit(batch_size).each do |upload|
        Community::ScanPostAttachmentJob.perform_later(upload_id: upload.id)
      end
    end

    private

    def adopt_unmanaged_attachments(now, limit)
      managed_ids = Community::Upload.where.not(forum_post_attachment_id: nil)
        .select(:forum_post_attachment_id)
      Community::PostAttachment
        .where.not(id: managed_ids)
        .order(:id)
        .limit(limit)
        .each do |attachment|
          next unless attachment.file.attached?

          Community::Upload.create_or_find_by!(post_attachment: attachment) do |upload|
            upload.user = attachment.user
            upload.public_id = Community::Upload.generate_public_id
            upload.kind = "post_attachment"
            upload.status = attachment.linked? ? "linked" : "stored"
            upload.byte_size = [ attachment.byte_size.to_i, attachment.file.blob.byte_size, 1 ].max
            upload.blob = attachment.file.blob
            upload.post = attachment.post
            upload.expires_at = Community::StoreUpload::PENDING_TTL.from_now unless attachment.linked?
            upload.scan_status = "pending"
            upload.next_scan_at = now
          end
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
          Rails.logger.warn(
            "[Maintenance::ScanForumAttachmentsJob] legacy adoption skipped " \
            "attachment_id=#{attachment.id} error=#{error.class}"
          )
        end
    end

    def normalized_batch_size(value)
      configured = Integer(
        value || SiteSetting.get("forum.attachments.scan_batch_size", DEFAULT_BATCH_SIZE.to_s),
        exception: false
      )
      configured&.between?(1, 1_000) ? configured : DEFAULT_BATCH_SIZE
    end
  end
end
