# frozen_string_literal: true

module Community
  class SearchController < ApplicationController
    def index
      @query = params[:q].to_s.strip
      return if @query.blank?

      @topics = Community::Topic
        .where(status: :published)
        .where("title ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%")
        .order(last_posted_at: :desc)
        .limit(20)

      @posts = Community::Post
        .where(status: :published)
        .where("body ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%")
        .order(created_at: :desc)
        .limit(20)
    end
  end
end
