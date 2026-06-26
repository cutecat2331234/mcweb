# frozen_string_literal: true

module Community
  # Public renderer for admin-managed forum pages.
  class PagesController < ApplicationController
    def show
      page = Community::ForumPage.published.find_by!(slug: params[:slug])
      formatted = Community::FormatPostBody.call(body: page.body)

      render inertia: "Community/Pages/Show", props: {
        page: {
          title: page.title,
          body_html: formatted.success? ? formatted.value : ERB::Util.html_escape(page.body)
        }
      }
    rescue ActiveRecord::RecordNotFound
      redirect_to forum_path, alert: t("mcweb.flash.forum_page_missing")
    end
  end
end
