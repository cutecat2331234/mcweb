# frozen_string_literal: true

module Community
  class TrustLevel
    LEVELS = [
      { level: 0, name: "新成员", min_posts: 0 },
      { level: 1, name: "基本用户", min_posts: 1 },
      { level: 2, name: "成员", min_posts: 10 },
      { level: 3, name: "常客", min_posts: 50 },
      { level: 4, name: "领导者", min_posts: 200 }
    ].freeze

    def self.level_info(user)
      return LEVELS.first unless user

      count = Community::Post.where(user: user, status: :published).count
      LEVELS.reverse.find { |entry| count >= entry[:min_posts] } || LEVELS.first
    end

    def self.level_for(user)
      level_info(user)[:level]
    end

    def self.can_send_pm?(user)
      return true if user&.permission?("forum.topics.lock") || user&.permission?("admin.access")

      level_for(user) >= 1
    end

    def self.can_post_links?(user)
      return true if user&.permission?("forum.topics.lock")

      level_for(user) >= 1
    end

    def self.contains_link?(text)
      text.to_s.match?(/https?:\/\//i)
    end

    def self.progress_for(user)
      return nil unless user

      count = Community::Post.where(user: user, status: :published).count
      current = level_info(user)
      next_entry = LEVELS.find { |entry| entry[:level] == current[:level] + 1 }
      posts_needed = next_entry ? [ next_entry[:min_posts] - count, 0 ].max : 0

      {
        level: current[:level],
        name: current[:name],
        posts_count: count,
        next_level: next_entry&.dig(:level),
        next_level_name: next_entry&.dig(:name),
        posts_needed: posts_needed,
        can_send_pm: can_send_pm?(user),
        can_post_links: can_post_links?(user)
      }
    end
  end
end
