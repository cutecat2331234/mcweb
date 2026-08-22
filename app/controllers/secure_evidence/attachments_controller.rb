# frozen_string_literal: true

module SecureEvidence
  class AttachmentsController < ApplicationController
    before_action :require_login
    before_action :rate_limit_upload!, only: :create
    before_action :set_attachment, only: %i[show scan_status]

    def create
      result = SecureEvidence::CreateAttachment.call(
        actor: current_user,
        subject_key: params[:subject_key],
        subject_public_id: params[:subject_public_id],
        file: params[:file],
        idempotency_key: params[:idempotency_key]
      )
      return render_service_error(result) if result.failure?

      response.set_header("Cache-Control", "private, no-store")
      render json: serialize_attachment(
        result.value.fetch(:attachment),
        idempotent: result.value.fetch(:idempotent)
      ), status: result.value.fetch(:idempotent) ? :ok : :created
    end

    def show
      return head :not_found unless authorized_subject?
      return head :gone if @attachment.state_purged?
      return head :locked unless AttachmentAccess.download_allowed?(@attachment, actor: current_user)

      record_download!
      blob = @attachment.blob
      set_download_headers(blob)
      self.response_body = streamed_blob(blob)
    rescue ActiveStorage::FileNotFoundError
      head :gone
    end

    def scan_status
      return head :not_found unless authorized_subject?

      response.set_header("Cache-Control", "private, no-store")
      render json: serialize_attachment(@attachment, idempotent: true)
    end

    private

    def set_attachment
      @attachment = Attachment.find_by!(public_id: params[:id])
    end

    def authorized_subject?
      AttachmentAccess.subject_download_allowed?(@attachment, actor: current_user)
    end

    def record_download!
      digest = Digest::SHA256.hexdigest(request.request_id.to_s).first(32)
      Attachment.transaction do
        @attachment.lock!
        raise ActiveRecord::RecordNotFound unless AttachmentAccess.download_allowed?(
          @attachment,
          actor: current_user
        )

        EventRecorder.record!(
          attachment: @attachment,
          actor: current_user,
          event_type: "downloaded",
          idempotency_key: "evidence:download:#{@attachment.id}:#{digest}",
          metadata: { download_request_id: digest },
          at: Time.current
        )
      end
    end

    def set_download_headers(blob)
      response.headers["Content-Type"] = @attachment.content_type
      response.headers["Content-Disposition"] = ActionDispatch::Http::ContentDisposition.format(
        disposition: "attachment",
        filename: @attachment.filename
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
        blob.download { |chunk| stream << chunk }
      end
    end

    def serialize_attachment(attachment, idempotent:)
      upload = attachment.upload_record
      {
        public_id: attachment.public_id,
        filename: attachment.filename,
        content_type: attachment.content_type,
        byte_size: attachment.byte_size,
        sha256: attachment.sha256,
        state: attachment.state,
        scan_status: upload&.scan_status || "pending",
        retention_until: attachment.retention_until.iso8601,
        idempotent:,
        download_url: secure_evidence_attachment_path(attachment),
        scan_status_url: scan_status_secure_evidence_attachment_path(attachment)
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
      render json: { error: "rate_limited", message: t("mcweb.flash.rate_limited") },
        status: :too_many_requests
    end

    def render_service_error(result)
      response.set_header("Cache-Control", "private, no-store")
      render json: { error: result.code, message: service_error_message(result) },
        status: service_error_status(result)
    end
  end
end
