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
      label = names.presence&.join(I18n.t("mcweb.commerce.list_separator")) || I18n.t("mcweb.forum.validate_section_tags.default_label")
      I18n.t("mcweb.forum.validate_section_tags.required", label: label)
    end
  end
end
