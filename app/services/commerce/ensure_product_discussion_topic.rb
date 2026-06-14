# frozen_string_literal: true

module Commerce
  class EnsureProductDiscussionTopic < ApplicationService
    def initialize(product:, creator: nil)
      @product = product
      @creator = creator
    end

    def call
      return ServiceResult.success(@product.forum_topic) if @product.forum_topic_id.present? && @product.forum_topic

      section = discussion_section
      return ServiceResult.failure(error: "未配置商品讨论分区。") unless section

      author = @creator || system_user
      return ServiceResult.failure(error: "无法创建讨论帖。") unless author

      body = <<~BODY.strip
        欢迎在此讨论 **#{@product.name}**。

        /store/products/#{@product.public_id}
      BODY

      result = Community::CreateTopic.call(
        user: author,
        section: section,
        title: "[商品] #{@product.name}",
        body: body
      )

      return result unless result.success?

      topic = result.value
      @product.update!(forum_topic_id: topic.id)
      ServiceResult.success(topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def discussion_section
      slug = SiteSetting.get("store.product_discussion_section_slug").to_s.strip
      section = Community::Section.find_by(slug: slug) if slug.present?
      section || Community::Section.order(:position).first
    end

    def system_user
      User.where(status: :active).order(:id).first
    end
  end
end
