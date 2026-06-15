# frozen_string_literal: true

module Community
  class SyncTopicTags < ApplicationService
    MAX_TAGS = 5

    def initialize(topic:, tag_names:, user: nil)
      @topic = topic
      @user = user
      @tag_names = Array(tag_names).flat_map { |n| n.to_s.split(",") }.map(&:strip).reject(&:blank?).first(MAX_TAGS)
    end

    def call
      @tag_names.each do |name|
        slug = name.to_s.parameterize.presence
        next unless slug

        tag = Community::Tag.find_by(slug: slug)
        tag = tag&.effective_tag
        if tag&.staff_only? && !can_use_staff_tags?
          return ServiceResult.failure(error: "You cannot use restricted tag: #{tag.name}")
        end
      end

      tags = @tag_names.filter_map do |name|
        tag = Community::Tag.find_or_create_by_name!(name, user: @user)
        tag&.effective_tag
      end.uniq

      allowed = Array(@topic.section.allowed_tag_ids).map(&:to_i).reject(&:zero?)
      if allowed.any?
        invalid = tags.reject { |tag| allowed.include?(tag.id) }
        if invalid.any?
          names = invalid.map(&:name).join("、")
          return ServiceResult.failure(error: "此分区不允许使用以下标签：#{names}")
        end
      end

      @topic.topic_tags.where.not(forum_tag_id: tags.map(&:id)).destroy_all
      tags.each do |tag|
        Community::TopicTag.find_or_create_by!(topic: @topic, tag: tag)
      end

      tag_ids = tags.map(&:id)

      required_result = Community::ValidateSectionRequiredTags.call(
        section: @topic.section,
        tag_ids: tag_ids
      )
      return required_result if required_result.failure?

      group_result = Community::ValidateTagGroups.call(tag_ids: tag_ids)
      return group_result if group_result.failure?

      section_group_result = Community::ValidateSectionTagGroups.call(
        section: @topic.section,
        tag_ids: tag_ids
      )
      return section_group_result if section_group_result.failure?

      ServiceResult.success(tags: tags)
    end

    private

    def can_use_staff_tags?
      return false unless @user

      @user.permission?("forum.tags.manage") || @user.permission?("admin.access")
    end
  end
end
