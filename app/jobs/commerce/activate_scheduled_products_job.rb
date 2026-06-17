# frozen_string_literal: true

module Commerce
  class ActivateScheduledProductsJob < ApplicationJob
    queue_as :maintenance

    def perform
      Commerce::Product
        .where(status: :draft)
        .where.not(available_at: nil)
        .where("available_at <= ?", Time.current)
        .find_each do |product|
          product.update!(status: :active, available_at: nil)
          Commerce::EnsureProductDiscussionTopic.call(product: product) if product.forum_topic_id.blank?
          Commerce::NotifyProductAvailableJob.perform_later(product.id)
        end

      Commerce::Product
        .where(status: :active)
        .where.not(unavailable_at: nil)
        .where("unavailable_at <= ?", Time.current)
        .find_each do |product|
          product.update!(status: :archived, unavailable_at: nil)
        end
    end
  end
end
