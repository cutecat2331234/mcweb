# frozen_string_literal: true

module Community
  # Public XenForo-style help center.
  class HelpController < ApplicationController
    def index
      articles = Community::HelpArticle.published.ordered
      grouped = articles.group_by(&:category).map do |category, items|
        {
          category: category,
          articles: items.map { |a| { title: a.title, slug: a.slug, url: forum_help_article_path(a.slug) } }
        }
      end

      render inertia: "Community/Help/Index", props: { categories: grouped }
    end

    def show
      article = Community::HelpArticle.published.find_by!(slug: params[:slug])
      formatted = Community::FormatPostBody.call(body: article.body)

      render inertia: "Community/Help/Show", props: {
        article: {
          title: article.title,
          category: article.category,
          body_html: formatted.success? ? formatted.value : ERB::Util.html_escape(article.body)
        }
      }
    rescue ActiveRecord::RecordNotFound
      redirect_to forum_help_path, alert: t("mcweb.flash.help_article_missing")
    end
  end
end
