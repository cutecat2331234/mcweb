# frozen_string_literal: true

module Community
  class FetchProductOnebox < ApplicationService
    PRODUCT_PATH = %r{\A(?:/app)?/store/products/([\w-]+)\z}i

    def initialize(url:)
      @url = url.to_s.strip
    end

    def call
      path = if @url.start_with?("/")
               @url
      else
               URI.parse(@url).path
      end
      return ServiceResult.success(nil) unless path

      match = path.match(PRODUCT_PATH)
      return ServiceResult.success(nil) unless match

      product = Commerce::Product.available.find_by(public_id: match[1]) ||
                Commerce::Product.available.find_by(slug: match[1])
      return ServiceResult.success(nil) unless product

      ServiceResult.success(
        public_id: product.public_id,
        name: product.name,
        summary: product.summary,
        price_label: format_price(product),
        image_url: product_image_url(product),
        url: "/app/store/products/#{product.public_id}"
      )
    rescue URI::InvalidURIError
      ServiceResult.success(nil)
    end

    private

    def format_price(product)
      cents = product.price_cents
      unit = product.currency == "CNY" ? "¥" : "$"
      ActionController::Base.helpers.number_to_currency(cents / 100.0, unit: unit)
    end

    def product_image_url(product)
      if product.cover_image.attached?
        Rails.application.routes.url_helpers.rails_blob_path(product.cover_image, only_path: true)
      else
        src = product.image_url.to_s.strip
        UrlSafety.safe_image_src?(src) ? src : nil
      end
    end
  end
end
