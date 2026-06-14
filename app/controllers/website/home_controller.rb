# frozen_string_literal: true

module Website
  class HomeController < ApplicationController
    layout "website"
    skip_installation_guard only: :index

    def index
      @featured_articles = Website::Article.published.order(published_at: :desc).limit(6)
    rescue ActiveRecord::StatementInvalid
      @featured_articles = []
    end
  end
end
