# frozen_string_literal: true

module Website
  class PagesController < ApplicationController
    def show
      page = Website::Page.published.find_by!(slug: params[:slug])
      blocks = page.blocks.visible_blocks.ordered.map do |block|
        settings = block.settings.deep_dup
        if block.block_type == "rich_text" && settings["html"].present?
          result = Website::BlockSanitizer.call(html: settings["html"])
          settings["html"] = result.success? ? result.value.to_s : ""
        end
        serialize_page_block(block).merge(settings: settings)
      end

      render inertia: "Website/Pages/Show", props: {
        page: { title: page.title, slug: page.slug },
        blocks: blocks
      }
    end
  end
end
