# frozen_string_literal: true

module Community
  class UploadsController < ApplicationController
    before_action :require_login
    before_action :rate_limit_upload!, only: :create

    MAX_SIZE = 5.megabytes
    ALLOWED_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze

    def create
      unless Community::TrustLevel.can_upload_images?(current_user)
        return render json: { error: t("mcweb.services.errors.new_members_cannot_upload_images") }, status: :forbidden
      end

      file = params[:file]
      return render json: { error: t("mcweb.services.errors.upload_file_required") }, status: :unprocessable_entity unless file

      max = max_upload_size
      if file.size > max
        return render json: { error: t("mcweb.services.errors.image_upload_too_large", max: "#{max / 1.megabyte}MB") }, status: :unprocessable_entity
      end

      unless ALLOWED_TYPES.include?(file.content_type)
        return render json: { error: t("mcweb.services.errors.unsupported_upload_type") }, status: :unprocessable_entity
      end

      blob = ActiveStorage::Blob.create_and_upload!(
        io: file,
        filename: file.original_filename,
        content_type: file.content_type
      )

      url = rails_blob_path(blob, only_path: true)
      render json: {
        url: url,
        markdown: "![#{file.original_filename}](#{url})"
      }
    end

    private

    def max_upload_size
      mb = SiteSetting.get("forum.max_upload_size_mb", (MAX_SIZE / 1.megabyte).to_s).to_i
      [ mb, 1 ].max.megabytes
    end

    def rate_limit_upload!
      result = Administration::RateLimiter.call(
        key: "forum_upload:#{current_user.id}",
        limit: 30,
        window: 1.hour
      )
      return unless result.failure?

      render json: { error: t("mcweb.flash.rate_limited") }, status: :too_many_requests
    end
  end
end
