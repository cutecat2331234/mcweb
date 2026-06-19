# frozen_string_literal: true

module Community
  class UploadsController < ApplicationController
    before_action :require_login

    MAX_SIZE = 5.megabytes
    ALLOWED_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze

    def create
      unless Community::TrustLevel.can_upload_images?(current_user)
        return render json: { error: "新成员暂不能上传图片，多发帖后即可解锁。" }, status: :forbidden
      end

      file = params[:file]
      return render json: { error: "请选择要上传的文件。" }, status: :unprocessable_entity unless file

      if file.size > MAX_SIZE
        return render json: { error: "文件过大（最大 5MB）。" }, status: :unprocessable_entity
      end

      unless ALLOWED_TYPES.include?(file.content_type)
        return render json: { error: "不支持的文件类型。" }, status: :unprocessable_entity
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
  end
end
