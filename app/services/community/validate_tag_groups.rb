# frozen_string_literal: true

module Community
  class ValidateTagGroups < ApplicationService
    def initialize(tag_ids:)
      @tag_ids = Array(tag_ids).map(&:to_i).uniq
    end

    def call
      Community::TagGroup.includes(:tags).find_each do |group|
        group_tag_ids = group.tag_ids
        next if group_tag_ids.empty?

        selected = @tag_ids & group_tag_ids
        if group.one_per_topic? && selected.size > 1
          names = Community::Tag.where(id: selected).pluck(:name).join(I18n.t("mcweb.commerce.list_separator"))
          return ServiceResult.failure(error: I18n.t("mcweb.services.errors.tag_group_single_only", group: group.name, names: names))
        end
      end

      ServiceResult.success
    end
  end
end
