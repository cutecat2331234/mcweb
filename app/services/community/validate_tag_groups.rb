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
          names = Community::Tag.where(id: selected).pluck(:name).join("、")
          return ServiceResult.failure(error: "标签组「#{group.name}」每个主题只能选一个标签，当前选了：#{names}")
        end
      end

      ServiceResult.success
    end
  end
end
