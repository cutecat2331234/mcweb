# frozen_string_literal: true

module Website
  class SerializePageBlocks < ApplicationService
    def initialize(page:)
      @page = page
    end

    def call
      blocks = @page.blocks.visible_blocks.reorder(:position).map do |block|
        settings = block.settings.deep_dup
        if block.block_type == "rich_text" && settings["html"].present?
          result = Website::BlockSanitizer.call(html: settings["html"])
          settings["html"] = result.success? ? result.value.to_s : ""
        elsif block.block_type == "hero" && settings["cta_url"].present?
          settings["cta_url"] = Website::SafeLink.sanitize_href(settings["cta_url"])
        end
        {
          block_type: block.block_type,
          settings: settings,
          position: block.position,
          visible: block.visible
        }
      end
      ServiceResult.success(blocks)
    end
  end
end
