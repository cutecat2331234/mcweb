# frozen_string_literal: true

module Community
  class ForumDigestJob < ApplicationJob
    queue_as :mailers

    def perform
      User.where(forum_digest_frequency: %w[daily weekly]).find_each do |user|
        Community::SendForumDigest.call(user: user)
      end
    end
  end
end
