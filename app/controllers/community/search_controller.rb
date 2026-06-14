# frozen_string_literal: true

module Community
  class SearchController < ApplicationController
    def index
      query = params[:q].to_s.strip
      topics = []
      posts = []

      if query.present?
        topics = Community::Topic
          .where(status: :published)
          .where("title ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(query)}%")
          .order(last_posted_at: :desc)
          .limit(20)

        posts = Community::Post
          .where(status: :published)
          .where("body ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(query)}%")
          .includes(:user, :topic)
          .order(created_at: :desc)
          .limit(20)
      end

      render inertia: "Community/Search/Index", props: {
        query: query,
        topics: topics.map { |topic| serialize_search_topic(topic) },
        posts: posts.map { |post| serialize_search_post(post) }
      }
    end
  end
end
