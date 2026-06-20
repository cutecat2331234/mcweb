# frozen_string_literal: true

module Admin
  module Store
    class UploadsController < BaseController
      before_action -> { require_permission("store.products.manage") }

      MAX_SIZE = 8.megabytes
      ALLOWED_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze

      def create
        file = params[:file]
        return render json: { error: t("mcweb.admin.store.uploads.file_required") }, status: :unprocessable_entity unless file

        if file.size > MAX_SIZE
          return render json: { error: t("mcweb.admin.store.uploads.file_too_large") }, status: :unprocessable_entity
        end

        unless ALLOWED_TYPES.include?(file.content_type)
          return render json: { error: t("mcweb.admin.store.uploads.unsupported_type") }, status: :unprocessable_entity
        end

        blob = ActiveStorage::Blob.create_and_upload!(
          io: file,
          filename: file.original_filename,
          content_type: file.content_type
        )

        product = nil
        attached = false
        if params[:product_id].present?
          product = Commerce::Product.find_by!(public_id: params[:product_id])
          attach_result = Commerce::AttachProductCover.call(product: product, signed_id: blob.signed_id)
          attached = attach_result.success?
        end

        url = rails_blob_path(blob, only_path: true)
        render json: {
          url: url,
          signed_id: blob.signed_id,
          attached_to_product: attached
        }
      end
    end
  end
end
