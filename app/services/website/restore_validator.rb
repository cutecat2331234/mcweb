# frozen_string_literal: true

module Website
  class RestoreValidator < ApplicationService
    def initialize(content:, snapshot: nil)
      @content = content
      @snapshot = (snapshot || {}).to_h.stringify_keys
    end

    def call
      blockers = []
      slug = @snapshot["slug"].presence || @content.slug
      page_type = @snapshot["page_type"].presence || (@content.page_type if @content.is_a?(Website::Page))

      blockers << "website_restore_slug_conflict" if slug_conflict?(slug)
      if @content.is_a?(Website::Page)
        blockers << "website_restore_home_conflict" if home_conflict?(page_type)
        blockers << "website_restore_theme_missing" if theme_missing?
        blockers << "website_restore_block_type_invalid" if invalid_block_types?
        blockers << "website_restore_navigation_conflict" if navigation_conflict?
      end

      ServiceResult.success(allowed: blockers.empty?, blockers: blockers.uniq)
    end

    private

    def slug_conflict?(slug)
      @content.class.where(slug: slug).where.not(id: @content.id).exists?
    end

    def home_conflict?(page_type)
      return false unless page_type == "home"

      Website::Page.where(page_type: "home").where.not(id: @content.id).exists?
    end

    def theme_missing?
      theme_id = if @snapshot.key?("website_theme_id")
        @snapshot["website_theme_id"]
      else
        @content.website_theme_id
      end
      theme_id.present? && !Website::Theme.exists?(id: theme_id)
    end

    def invalid_block_types?
      block_types = if @snapshot.key?("blocks")
        Array(@snapshot["blocks"]).map { |block| block.to_h.stringify_keys["block_type"] }
      else
        @content.blocks.unscope(:order).pluck(:block_type)
      end
      (block_types.compact.uniq - Website::Block::SUPPORTED_TYPES).any?
    end

    def navigation_conflict?
      slug = @snapshot["slug"].presence || @content.slug
      malformed_reference = Website::NavItem.where(website_page_id: @content.id).any? do |item|
        item.url.present? || item.label.blank? || item.location.blank?
      end
      duplicate_path = Website::NavItem.visible_items.where(url: "/#{slug}").exists?
      malformed_reference || duplicate_path
    end
  end
end
