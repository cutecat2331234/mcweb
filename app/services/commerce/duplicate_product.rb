# frozen_string_literal: true

module Commerce
  class DuplicateProduct < ApplicationService
    def initialize(product:)
      @product = product
    end

    def call
      copy = nil
      Commerce::Product.transaction do
        copy = @product.dup
        copy.public_id = "prod_#{SecureRandom.alphanumeric(16)}"
        copy.slug = unique_slug("#{@product.slug}-copy")
        copy.name = "#{@product.name}#{I18n.t('mcweb.commerce.product_duplicate_suffix')}"
        copy.status = "draft"
        copy.view_count = 0
        copy.forum_topic_id = nil
        copy.save!

        @product.variants.each do |variant|
          copy.variants.create!(
            name: variant.name,
            sku: unique_sku(variant.sku),
            price_cents: variant.price_cents,
            compare_at_price_cents: variant.compare_at_price_cents,
            stock: variant.stock,
            fulfillment_config: variant.fulfillment_config.deep_dup
          )
        end
      end

      ServiceResult.success(copy)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def unique_slug(base)
      slug = base
      counter = 2
      while Commerce::Product.exists?(slug: slug)
        slug = "#{base}-#{counter}"
        counter += 1
      end
      slug
    end

    def unique_sku(base)
      sku = "#{base}-COPY"
      counter = 2
      while Commerce::ProductVariant.exists?(sku: sku)
        sku = "#{base}-COPY#{counter}"
        counter += 1
      end
      sku
    end
  end
end
