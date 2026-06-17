# frozen_string_literal: true

module Community
  class ValidateSectionTagGroups < ApplicationService
    def initialize(section:, tag_ids:)
      @section = section
      @tag_ids = Array(tag_ids).map(&:to_i).uniq
    end

    def call
      required_group_ids = Array(@section.required_tag_group_ids).map(&:to_i).reject(&:zero?)
      return ServiceResult.success if required_group_ids.empty?

      required_group_ids.each do |group_id|
        group = Community::TagGroup.find_by(id: group_id)
        next unless group

        group_tag_ids = group.tag_ids
        next if group_tag_ids.empty?

        unless (@tag_ids & group_tag_ids).any?
          return ServiceResult.failure(error: "此分区要求从标签组「#{group.name}」中至少选择一个标签。")
        end
      end

      ServiceResult.success
    end
  end
end
