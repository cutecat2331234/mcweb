# frozen_string_literal: true

module Community
  module SectionTagGroupsSerializable
    extend ActiveSupport::Concern

    private

    def section_tag_groups_for(section, user: current_user)
      allowed_ids = section.allowed_tag_ids.presence
      allowed_set = allowed_ids ? allowed_ids.map(&:to_i).to_set : nil
      usable_ids = Community::Tag.usable_by(user).pluck(:id).to_set

      Community::TagGroup.includes(:tags).ordered.filter_map do |group|
        tags = group.tags.select do |tag|
          usable_ids.include?(tag.id) && (allowed_set.nil? || allowed_set.include?(tag.id))
        end
        next if tags.empty?

        {
          name: group.name,
          slug: group.slug,
          color_hex: group.color_hex,
          one_per_topic: group.one_per_topic?,
          tags: tags.map { |tag| { name: tag.name, slug: tag.slug, color_hex: tag.color_hex } }
        }
      end
    end
  end
end
