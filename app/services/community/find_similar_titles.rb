# frozen_string_literal: true

module Community
  class FindSimilarTitles < ApplicationService
    def initialize(section:, title:, limit: 5)
      @section = section
      @title = title.to_s.strip
      @limit = limit.to_i.clamp(1, 10)
    end

    def call
      return ServiceResult.success(titles: []) if @title.length < 3

      needle = ActiveRecord::Base.sanitize_sql_like(@title)
      topics = Community::Topic
        .published_listed
        .where(forum_section_id: @section.id)
        .where("title ILIKE ?", "%#{needle}%")
        .order(last_posted_at: :desc)
        .limit(@limit)

      ServiceResult.success(
        titles: topics.map do |topic|
          {
            title: topic.title,
            url: "#{Mcweb::Paths::APP_PREFIX}/forum/topics/#{topic.public_id}",
            last_posted_at: topic.last_posted_at
          }
        end
      )
    end
  end
end
