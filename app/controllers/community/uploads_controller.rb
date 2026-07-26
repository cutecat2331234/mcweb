# frozen_string_literal: true

module Community
  class UploadsController < ApplicationController
    INLINE_CONTENT_TYPES = %w[image/png image/jpeg].freeze

    before_action :require_login, only: :create
    before_action :rate_limit_upload!, only: :create
    before_action :set_upload, only: :show

    MAX_SIZE = 5.megabytes
    def create
      unless Community::TrustLevel.can_upload_images?(current_user)
        return render json: { error: t("mcweb.services.errors.new_members_cannot_upload_images") }, status: :forbidden
      end

      file = params[:file]
      return render json: { error: t("mcweb.services.errors.upload_file_required") }, status: :unprocessable_entity unless file

      inspection = Community::ImageUploadInspector.call(io: file, max_bytes: max_upload_size)
      if inspection.too_large?
        max = max_upload_size
        return render json: { error: t("mcweb.services.errors.image_upload_too_large", max: "#{max / 1.megabyte}MB") }, status: :unprocessable_entity
      end

      unless inspection.success?
        return render json: { error: t("mcweb.services.errors.unsupported_upload_type") }, status: :unprocessable_entity
      end

      filename = safe_image_filename(file.original_filename, inspection.extension)
      stored = Community::StoreUpload.call(
        user: current_user,
        kind: :inline_image,
        payload: inspection.payload,
        filename: filename,
        content_type: inspection.content_type
      )
      unless stored.success?
        return render json: { error: service_error_message(stored) }, status: :unprocessable_entity
      end

      upload = stored.value.fetch(:upload)
      url = forum_upload_path(upload.public_id)
      render json: {
        url: url,
        markdown: "![#{filename}](#{url})"
      }
    end

    def show
      return head :forbidden unless inline_upload_readable?

      blob = @upload.blob
      response.headers["Content-Type"] = blob.content_type
      response.headers["Content-Disposition"] = ActionDispatch::Http::ContentDisposition.format(
        disposition: "inline",
        filename: blob.filename.sanitized
      )
      response.headers["Content-Length"] = blob.byte_size.to_s
      response.headers["Cache-Control"] = "private, no-store"
      response.headers["Pragma"] = "no-cache"
      response.headers["X-Content-Type-Options"] = "nosniff"
      response.headers["Content-Security-Policy"] = "sandbox"
      response.headers["Cross-Origin-Resource-Policy"] = "same-origin"
      self.response_body = streamed_blob(blob)
    end

    private

    def set_upload
      @upload = Community::Upload.find_by!(
        public_id: params[:id],
        kind: "inline_image"
      )
    end

    def inline_upload_readable?
      return false unless @upload.scan_clean?
      return false unless @upload.status_stored? || @upload.status_linked?
      return false unless INLINE_CONTENT_TYPES.include?(@upload.blob&.content_type)

      if @upload.status_linked?
        post = @upload.post
        post && Community::PostAccess.readable?(post: post, user: current_user)
      else
        @upload.expires_at&.>(Time.current) && current_user&.id == @upload.user_id
      end
    end

    def streamed_blob(blob)
      Enumerator.new do |stream|
        blob.download do |chunk|
          stream << chunk
        end
      end
    end

    def max_upload_size
      mb = SiteSetting.get("forum.max_upload_size_mb", (MAX_SIZE / 1.megabyte).to_s).to_i
      [ mb, 1 ].max.megabytes
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

    def safe_image_filename(original_name, extension)
      stem = File.basename(original_name.to_s, ".*")
        .gsub(/[^\w\-() ]+/u, "_")
        .strip
        .first(160)
        .presence || "image"
      "#{stem}.#{extension}"
    end
  end
end
