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
      return ServiceResult.failure(error: "discussion_section_missing") unless section

      author = @creator || system_user
      return ServiceResult.failure(error: "discussion_topic_create_failed") unless author

      result = Community::CreateTopic.call(
        user: author,
        section: section,
        title: I18n.t("mcweb.commerce.discussion.topic_title", name: @product.name),
        body: I18n.t("mcweb.commerce.discussion.topic_body", name: @product.name)
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
