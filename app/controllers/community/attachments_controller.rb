# frozen_string_literal: true

module Community
  class AttachmentsController < ApplicationController
    before_action :require_login, only: %i[create scan_status]
    before_action :rate_limit_upload!, only: :create
    before_action :set_attachment, only: %i[show scan_status]

    def create
      result = Community::CreatePostAttachment.call(user: current_user, file: params[:file])
      if result.success?
        attachment = result.value
        render json: serialize_attachment(attachment)
      else
        render json: { error: service_error_message(result) }, status: :unprocessable_entity
      end
    end

    def show
      return head :forbidden unless Community::PostAttachmentAccess.downloadable?(@attachment, user: current_user)
      return head :locked unless @attachment.scan_clean?

      blob = @attachment.file.blob
      @attachment.increment!(:download_count)
      set_download_headers(blob)
      self.response_body = streamed_blob(blob)
    end

    def scan_status
      return head :forbidden unless @attachment.user_id == current_user.id

      upload = @attachment.upload_record
      return render json: { scan_status: "pending" } unless upload

      payload = {
        scan_status: upload.scan_status,
        retryable: upload.scan_status_error? && upload.next_scan_at.present?,
        next_scan_at: upload.next_scan_at&.iso8601
      }
      payload[:attachment] = serialize_attachment(@attachment) if upload.scan_clean?
      render json: payload
    end

    private

    def set_attachment
      @attachment = Community::PostAttachment.find(params[:id])
    end

    def set_download_headers(blob)
      filename = @attachment.filename.presence || blob.filename.sanitized
      response.headers["Content-Type"] = Community::AllowedAttachmentTypes.download_content_type(filename)
      response.headers["Content-Disposition"] = ActionDispatch::Http::ContentDisposition.format(
        disposition: "attachment",
        filename: filename
      )
      response.headers["Content-Length"] = blob.byte_size.to_s
      response.headers["Cache-Control"] = "private, no-store"
      response.headers["Pragma"] = "no-cache"
      response.headers["X-Content-Type-Options"] = "nosniff"
      response.headers["Content-Security-Policy"] = "sandbox"
      response.headers["Cross-Origin-Resource-Policy"] = "same-origin"
    end

    def streamed_blob(blob)
      Enumerator.new do |stream|
        blob.download do |chunk|
          stream << chunk
        end
      end
    end

    def serialize_attachment(attachment)
      {
        id: attachment.id,
        filename: attachment.filename,
        content_type: attachment.content_type,
        byte_size: attachment.byte_size,
        human_size: attachment.human_size,
        download_url: forum_attachment_path(attachment),
        scan_status: attachment.upload_record&.scan_status || "pending",
        scan_status_url: scan_status_forum_attachment_path(attachment)
      }
    end

    def rate_limit_upload!
      result = Administration::AbuseRateLimit.call(
        action: :upload,
        account: current_user,
        ip_address: request.remote_ip
      )
      return unless result.failure?

      apply_retry_after_header(result)
      render json: { error: "rate_limited", message: t("mcweb.flash.rate_limited") }, status: :too_many_requests
    end
  end
end
