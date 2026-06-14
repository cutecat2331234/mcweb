# frozen_string_literal: true

module Community
  class BookmarksController < ApplicationController
    before_action :require_login

    def index
      bookmarks = Community::Bookmark.where(user: current_user).includes(:topic, :post)
      topic_bookmarks = bookmarks.select { |bookmark| bookmark.forum_post_id.nil? }
      post_bookmarks = bookmarks.select { |bookmark| bookmark.forum_post_id.present? }

      topic_ids = topic_bookmarks.map(&:forum_topic_id).uniq
      topics = Community::Topic
        .where(id: topic_ids, status: :published)
        .includes(:user, :section)
        .order(last_posted_at: :desc)
        .limit(50)
      topics = filter_blocked_topics(topics)

      read_states = Community::ReadState
        .where(user: current_user, forum_topic_id: topics.map(&:id))
        .index_by(&:forum_topic_id)

      post_items = post_bookmarks.filter_map do |bookmark|
        post = bookmark.post
        topic = bookmark.topic
        next if topic.nil? || topic.status != "published"
        next if blocked_user_ids.include?(topic.user_id)

        {
          id: post.id,
          floor_number: post.floor_number,
          excerpt: post.body.truncate(120),
          topic_title: topic.title,
          url: "#{forum_topic_path(topic)}#post-#{post.id}",
          created_at: l(bookmark.created_at, format: :short)
        }
      end

      render inertia: "Community/Bookmarks/Index", props: {
        topics: topics.map { |topic| serialize_topic(topic, read_state: read_states[topic.id]) },
        postBookmarks: post_items
      }
    end
  end
end
