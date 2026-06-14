# frozen_string_literal: true

module Commerce
  class AttachProductCover < ApplicationService
    def initialize(product:, signed_id:)
      @product = product
      @signed_id = signed_id
    end

    def call
      return ServiceResult.failure(error: "No image provided.") if @signed_id.blank?

      blob = ActiveStorage::Blob.find_signed!(@signed_id)
      @product.cover_image.attach(blob)
      url = Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
      @product.update!(image_url: url) if @product.image_url.blank?
      ServiceResult.success(url: url)
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
      ServiceResult.failure(error: "Invalid image upload.")
    end
  end
end
