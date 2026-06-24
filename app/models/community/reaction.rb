module Community
  class Reaction < ApplicationRecord
    belongs_to :user
    belongs_to :post, class_name: "Community::Post", foreign_key: :forum_post_id

    validates :emoji, presence: true
    validates :user_id, uniqueness: { scope: [ :forum_post_id, :emoji ] }

    def self.toggle!(user, post, emoji)
      reaction = find_by(user: user, post: post, emoji: emoji)
      if reaction
        reaction.destroy!
        false
      else
        create!(user: user, post: post, emoji: emoji)
        true
      end
    end

    # Optional per-emoji weights, e.g. "👍:1,❤️:2,👀:0". Unlisted emoji count as 1,
    # so with no setting the reaction score equals the flat reaction count.
    def self.score_map
      SiteSetting.get("forum.reaction_scores", "").to_s.split(/[,\s]+/).each_with_object({}) do |pair, map|
        emoji, score = pair.split(":", 2)
        map[emoji] = score.to_i if emoji.present? && score.present?
      end
    end

    def self.score_for(emoji)
      score_map.fetch(emoji.to_s, 1)
    end

    # XenForo-style weighted reaction score for all reactions a user has received.
    def self.score_for_user(user)
      map = score_map
      joins(:post).where(forum_posts: { user_id: user.id }).group(:emoji).count.sum do |emoji, count|
        count * map.fetch(emoji.to_s, 1)
      end
    end
  end
end
