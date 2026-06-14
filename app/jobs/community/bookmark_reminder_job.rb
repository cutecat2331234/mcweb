# frozen_string_literal: true

module Community
  class BookmarkReminderJob < ApplicationJob
    queue_as :notifications

    def perform
      Community::Bookmark
        .where.not(remind_at: nil)
        .where("remind_at <= ?", Time.current)
        .includes(:user, :topic, :post)
        .find_each do |bookmark|
          Community::NotifyBookmarkReminder.call(bookmark: bookmark)
        end
    end
  end
end
