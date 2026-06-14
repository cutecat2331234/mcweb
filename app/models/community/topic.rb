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
    has_many :topic_mutes, class_name: "Community::TopicMute", foreign_key: :forum_topic_id, dependent: :destroy
    has_many :topic_tags, class_name: "Community::TopicTag", foreign_key: :forum_topic_id, dependent: :destroy
    has_many :tags, through: :topic_tags, source: :tag
    has_many :bookmarks, class_name: "Community::Bookmark", foreign_key: :forum_topic_id, dependent: :destroy
    has_one :poll, class_name: "Community::Poll", foreign_key: :forum_topic_id, dependent: :destroy
    belongs_to :solved_post, class_name: "Community::Post", optional: true

    enum :status, { draft: "draft", published: "published", hidden: "hidden", deleted: "deleted" }, validate: true

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
      when "hot"
        order(Arel.sql("pinned DESC, (replies_count * 3 + views_count)::float / POWER(GREATEST(EXTRACT(EPOCH FROM (NOW() - last_posted_at)) / 3600.0, 0) + 2, 1.2) DESC"))
      else
        pinned_first
      end
    end

    def record_view!
      increment!(:views_count)
    end

    def related_by_tags(limit: 5)
      tag_ids = tags.pluck(:id)
      return Community::Topic.none if tag_ids.empty?

      Community::Topic
        .where(status: :published)
        .where.not(id: id)
        .joins(:tags)
        .where(forum_tags: { id: tag_ids })
        .group("forum_topics.id")
        .order(Arel.sql("COUNT(forum_topic_tags.id) DESC, forum_topics.last_posted_at DESC"))
        .limit(limit)
    end

    def lock_topic!
      update!(locked: true)
    end

    def unlock_topic!
      update!(locked: false)
    end
  end
end
