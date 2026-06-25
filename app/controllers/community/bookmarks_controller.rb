# frozen_string_literal: true

module Community
  class BookmarksController < ApplicationController
    include Community::TopicListPreloadable

    before_action :require_login
    before_action :set_bookmark, only: :update

    def index
      all_bookmarks = Community::Bookmark.where(user: current_user)
      labels = all_bookmarks.where.not(label: [ nil, "" ]).distinct.pluck(:label).sort
      active_label = params[:label].to_s.presence

      bookmarks = all_bookmarks.includes(:topic, :post)
      bookmarks = bookmarks.where(label: active_label) if active_label
      bookmarks = bookmarks.to_a
      topic_bookmarks = bookmarks.select { |bookmark| bookmark.forum_post_id.nil? }
      post_bookmarks = bookmarks.select { |bookmark| bookmark.forum_post_id.present? }

      topic_ids = topic_bookmarks.map(&:forum_topic_id).uniq
      topics = preload_topics(Community::Topic.where(id: topic_ids, status: :published).accessible_by(current_user).order(last_posted_at: :desc).limit(50))
      topics = filter_blocked_topics(topics)
      attach_participant_users!(topics)

      read_states = Community::ReadState
        .where(user: current_user, forum_topic_id: topics.map(&:id))
        .index_by(&:forum_topic_id)

      topic_items = topic_bookmarks.filter_map do |bookmark|
        topic = bookmark.topic
        next if topic.nil? || topic.status != "published"
        next if topic.unlisted?
        next if blocked_user_ids.include?(topic.user_id)

        {
          bookmark_id: bookmark.id,
          update_url: forum_bookmark_path(bookmark),
          note: bookmark.note,
          label: bookmark.label,
          remind_at: bookmark.remind_at ? l(bookmark.remind_at, format: :short) : nil,
          remind_at_input: bookmark.remind_at&.strftime("%Y-%m-%dT%H:%M"),
          topic: serialize_topic(topic, read_state: read_states[topic.id])
        }
      end

      post_items = post_bookmarks.filter_map do |bookmark|
        post = bookmark.post
        topic = bookmark.topic
        next if topic.nil? || topic.status != "published"
        next if topic.unlisted?
        next if blocked_user_ids.include?(topic.user_id)
        next unless Community::PostAccess.readable?(post: post, user: current_user)

        {
          id: post.id,
          bookmark_id: bookmark.id,
          update_url: forum_bookmark_path(bookmark),
          note: bookmark.note,
          label: bookmark.label,
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
        postBookmarks: post_items,
        labels: labels,
        activeLabel: active_label.to_s
      }
    end

    def update
      result = Community::UpdateBookmark.call(
        user: current_user,
        bookmark: @bookmark,
        note: bookmark_params[:note],
        remind_at: bookmark_params[:remind_at],
        label: bookmark_params[:label]
      )

      if result.success?
        redirect_to forum_bookmarks_path, notice: t("mcweb.flash.bookmark_updated")
      else
        redirect_to forum_bookmarks_path, alert: service_error_message(result)
      end
    end

    private

    def set_bookmark
      @bookmark = Community::Bookmark.find_by!(id: params[:id], user: current_user)
    end

    def bookmark_params
      params.require(:bookmark).permit(:note, :remind_at, :label)
    end
  end
end
