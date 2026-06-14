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
  end
end
