module Community
  class Post < ApplicationRecord
    include SoftDeletable

    belongs_to :topic, class_name: "Community::Topic", foreign_key: :forum_topic_id
    belongs_to :user
    belongs_to :quoted_post, class_name: "Community::Post", optional: true
    belongs_to :parent_post, class_name: "Community::Post", optional: true
    has_many :child_posts, class_name: "Community::Post", foreign_key: :parent_post_id, dependent: :nullify
    has_many :edits, class_name: "Community::PostEdit", foreign_key: :forum_post_id, dependent: :destroy
    has_many :reactions, class_name: "Community::Reaction", foreign_key: :forum_post_id, dependent: :destroy
    has_many :forked_topics, class_name: "Community::Topic", foreign_key: :source_post_id, dependent: :nullify

    enum :status, { published: "published", hidden: "hidden", deleted: "deleted" }, validate: true
    enum :post_type, { regular: "regular", small_action: "small_action" }, validate: true, prefix: true

    validates :body, presence: true
    validates :floor_number, presence: true, uniqueness: { scope: :forum_topic_id }

    scope :chronological, -> { order(:floor_number) }

    def small_action?
      post_type == "small_action"
    end

    def wiki_post?
      wiki == true
    end

    after_create :update_topic_counters

    def edit_body!(new_body, editor:, reason: nil)
      transaction do
        edits.create!(editor: editor, body_before: body, body_after: new_body, reason: reason)
        update!(body: new_body, edited_at: Time.current)
      end
    end

    private

    def update_topic_counters
      topic.update!(
        replies_count: [ topic.posts.count - 1, 0 ].max,
        last_posted_at: created_at,
        last_post_user: user
      )
    end
  end
end
