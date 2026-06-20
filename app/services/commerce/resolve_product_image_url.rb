# frozen_string_literal: true

module Commerce
  class ResolveProductImageUrl < ApplicationService
    def initialize(product:)
      @product = product
    end

    def call
      if @product.cover_image.attached?
        return ServiceResult.success(url: rails_blob_path(@product.cover_image))
      end

      pack_url = image_pack_texture_url
      return ServiceResult.success(url: pack_url) if pack_url.present?

      external = @product.image_url.to_s.strip
      return ServiceResult.success(url: external) if UrlSafety.safe_image_src?(external)

      ServiceResult.success(url: nil)
    end

    private

    def image_pack_texture_url
      config = @product.fulfillment_config || {}
      pack_id = config["image_pack"] || config["image_pack_id"] || config[:image_pack] || config[:image_pack_id]
      return nil if pack_id.blank?

      segments = texture_segments(config)
      return nil if segments.blank?
      return nil unless Mcweb::ImagePackRegistry.texture_path(pack_id, *segments)

      helpers.store_image_pack_texture_path(pack_id: pack_id, texture_path: segments.join("/"))
    end

    def texture_segments(config)
      raw = config["image_texture"] || config["image_pack_texture"] || config[:image_texture] || config[:image_pack_texture]
      case raw
      when Array
        raw.map(&:to_s).reject(&:blank?)
      when String
        raw.split("/").map(&:strip).reject(&:blank?)
      end
    end

    def rails_blob_path(attachment)
      Rails.application.routes.url_helpers.rails_blob_path(attachment, only_path: true)
    end

    def helpers
      Rails.application.routes.url_helpers
    end
  end
end
