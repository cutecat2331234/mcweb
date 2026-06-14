# frozen_string_literal: true

module Community
  class SyncTopicLastPost < ApplicationService
    def initialize(topic:)
      @topic = topic
    end

    def call
      published = @topic.posts.where(status: :published).order(:floor_number)
      last = published.last

      if last
        @topic.update!(
          last_posted_at: last.created_at,
          last_post_user: last.user,
          replies_count: [ published.count - 1, 0 ].max
        )
      else
        @topic.update!(replies_count: 0)
      end

      ServiceResult.success(@topic)
    end
  end
end
