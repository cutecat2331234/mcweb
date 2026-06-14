module Community
  class Topic < ApplicationRecord
    include HasPublicId
    include SoftDeletable

    belongs_to :section, class_name: "Community::Section", foreign_key: :forum_section_id
    belongs_to :user
    belongs_to :last_post_user, class_name: "User", optional: true
    has_many :posts, class_name: "Community::Post", foreign_key: :forum_topic_id, dependent: :destroy
    has_many :read_states, class_name: "Community::ReadState", foreign_key: :forum_topic_id, dependent: :destroy
    has_many :subscriptions, as: :subscribable, class_name: "Community::Subscription", dependent: :destroy
    has_many :topic_tags, class_name: "Community::TopicTag", foreign_key: :forum_topic_id, dependent: :destroy
    has_many :tags, through: :topic_tags, source: :tag
    has_many :bookmarks, class_name: "Community::Bookmark", foreign_key: :forum_topic_id, dependent: :destroy

    enum :status, { published: "published", hidden: "hidden", deleted: "deleted" }, validate: true

    validates :title, presence: true, length: { maximum: 255 }

    scope :pinned_first, -> { order(pinned: :desc, last_posted_at: :desc) }
    scope :recent, -> { order(last_posted_at: :desc) }
    scope :featured_topics, -> { where(featured: true, status: :published) }

    def self.sorted(sort)
      case sort.to_s
      when "views"
        order(pinned: :desc, views_count: :desc, last_posted_at: :desc)
      when "replies"
        order(pinned: :desc, replies_count: :desc, last_posted_at: :desc)
      when "newest"
        order(pinned: :desc, created_at: :desc)
      else
        pinned_first
      end
    end

    def record_view!
      increment!(:views_count)
    end

    def lock_topic!
      update!(locked: true)
    end

    def unlock_topic!
      update!(locked: false)
    end
  end
end
