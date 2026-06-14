# frozen_string_literal: true

module Community
  class BookmarksController < ApplicationController
    before_action :require_login
    before_action :set_bookmark, only: :update

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

      topic_items = topic_bookmarks.filter_map do |bookmark|
        topic = bookmark.topic
        next if topic.nil? || topic.status != "published"
        next if blocked_user_ids.include?(topic.user_id)

        {
          bookmark_id: bookmark.id,
          update_url: forum_bookmark_path(bookmark),
          note: bookmark.note,
          remind_at: bookmark.remind_at ? l(bookmark.remind_at, format: :short) : nil,
          remind_at_input: bookmark.remind_at&.strftime("%Y-%m-%dT%H:%M"),
          topic: serialize_topic(topic, read_state: read_states[topic.id])
        }
      end

      post_items = post_bookmarks.filter_map do |bookmark|
        post = bookmark.post
        topic = bookmark.topic
        next if topic.nil? || topic.status != "published"
        next if blocked_user_ids.include?(topic.user_id)

        {
          id: post.id,
          bookmark_id: bookmark.id,
          update_url: forum_bookmark_path(bookmark),
          note: bookmark.note,
          remind_at: bookmark.remind_at ? l(bookmark.remind_at, format: :short) : nil,
          remind_at_input: bookmark.remind_at&.strftime("%Y-%m-%dT%H:%M"),
          floor_number: post.floor_number,
          excerpt: post.body.truncate(120),
          topic_title: topic.title,
          url: "#{forum_topic_path(topic)}#post-#{post.id}",
          created_at: l(bookmark.created_at, format: :short)
        }
      end

      render inertia: "Community/Bookmarks/Index", props: {
        topics: topic_items,
        postBookmarks: post_items
      }
    end

    def update
      result = Community::UpdateBookmark.call(
        user: current_user,
        bookmark: @bookmark,
        note: bookmark_params[:note],
        remind_at: bookmark_params[:remind_at]
      )

      if result.success?
        redirect_to forum_bookmarks_path, notice: "书签已更新。"
      else
        redirect_to forum_bookmarks_path, alert: service_error_message(result)
      end
    end

    private

    def set_bookmark
      @bookmark = Community::Bookmark.find_by!(id: params[:id], user: current_user)
    end

    def bookmark_params
      params.require(:bookmark).permit(:note, :remind_at)
    end
  end
end
