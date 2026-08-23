# frozen_string_literal: true

module Website
  class PagesController < ApplicationController
    def show
      page = Website::Page.published.find_by!(slug: params[:slug])

      if page.page_type == "home" && Website::Page.cms_home.exists?
        redirect_to root_path, status: :moved_permanently
        return
      end

      blocks_result = Website::SerializePageBlocks.call(page: page)
      seo_result = Website::ResolveSeo.call(record: page)

      Frontend::WebsiteRenderer.call(
        controller: self,
        component: "Website/Pages/Show",
        props: {
          page: { title: page.title, slug: page.slug },
          blocks: blocks_result.value,
          seo: seo_result.value
        }
      )
    end
  end
end
