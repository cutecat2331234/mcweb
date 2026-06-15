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
    has_one :linked_product, class_name: "Commerce::Product", foreign_key: :forum_topic_id
    has_many :reply_bans, class_name: "Community::TopicReplyBan", foreign_key: :forum_topic_id, dependent: :destroy
    has_many :staff_notes, class_name: "Community::TopicStaffNote", foreign_key: :forum_topic_id, dependent: :destroy
    has_many :invites, class_name: "Community::TopicInvite", foreign_key: :forum_topic_id, dependent: :destroy
    belongs_to :solved_post, class_name: "Community::Post", optional: true
    belongs_to :source_post, class_name: "Community::Post", optional: true

    scope :global_announcements, -> { where(global_announcement: true, status: :published, unlisted: false) }

    enum :status, { draft: "draft", published: "published", hidden: "hidden", deleted: "deleted" }, validate: true

    validates :title, presence: true, length: { maximum: 255 }

    scope :pinned_first, -> { order(pinned: :desc, last_posted_at: :desc) }
    scope :recent, -> { order(last_posted_at: :desc) }
    scope :featured_topics, -> { where(featured: true, status: :published, unlisted: false) }
    scope :listed, -> { where(unlisted: false) }
    scope :published_listed, -> { where(status: :published, unlisted: false) }

    def unlisted?
      unlisted == true
    end

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

    attr_writer :participant_users_preloaded

    def participant_users(limit: 5)
      if @participant_users_preloaded
        return @participant_users_preloaded.first(limit)
      end

      ids = posts.where(status: :published)
        .where.not(user_id: user_id)
        .order(created_at: :desc)
        .pluck(:user_id)
        .uniq
        .first(limit)

      users_by_id = User.where(id: ids).index_by(&:id)
      ids.filter_map { |id| users_by_id[id] }
    end

    def related_by_tags(limit: 5)
      tag_ids = tags.pluck(:id)
      return Community::Topic.none if tag_ids.empty?

      Community::Topic
        .where(status: :published, unlisted: false)
        .where.not(id: id)
        .joins(:tags)
        .where(forum_tags: { id: tag_ids })
        .group("forum_topics.id")
        .order(Arel.sql("COUNT(forum_topic_tags.id) DESC, forum_topics.last_posted_at DESC"))
        .limit(limit)
    end

    def similar_topics(limit: 5)
      results = related_by_tags(limit: limit).to_a
      return results if results.size >= limit

      remaining = limit - results.size
      exclude_ids = [ id ] + results.map(&:id)
      section_topics = Community::Topic
        .where(status: :published, unlisted: false, forum_section_id: forum_section_id)
        .where.not(id: exclude_ids)
        .order(last_posted_at: :desc)
        .limit(remaining)
        .to_a

      results + section_topics
    end

    def lock_topic!
      update!(locked: true)
    end

    def unlock_topic!
      update!(locked: false)
    end
  end
end
