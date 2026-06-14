# frozen_string_literal: true

module Community
  class ValidateSectionRequiredTags < ApplicationService
    def initialize(section:, tag_ids:)
      @section = section
      @tag_ids = Array(tag_ids).map(&:to_i).uniq
    end

    def call
      required = Array(@section.required_tag_ids).map(&:to_i).reject(&:zero?)
      return ServiceResult.success if required.empty?
      return ServiceResult.failure(error: required_tags_error(required)) unless (@tag_ids & required).any?

      ServiceResult.success
    end

    private

    def required_tags_error(required)
      names = Community::Tag.where(id: required).order(:name).pluck(:name)
      label = names.presence&.join("、") || "指定标签"
      "此分区要求至少包含以下标签之一：#{label}"
    end
  end
end
