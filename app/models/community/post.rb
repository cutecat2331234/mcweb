module Community
  class Post < ApplicationRecord
    include SoftDeletable

    belongs_to :topic, class_name: "Community::Topic", foreign_key: :forum_topic_id
    belongs_to :user
    belongs_to :quoted_post, class_name: "Community::Post", optional: true
    has_many :edits, class_name: "Community::PostEdit", foreign_key: :forum_post_id, dependent: :destroy
    has_many :reactions, class_name: "Community::Reaction", foreign_key: :forum_post_id, dependent: :destroy

    enum :status, { published: "published", hidden: "hidden", deleted: "deleted" }, validate: true

    validates :body, presence: true
    validates :floor_number, presence: true, uniqueness: { scope: :forum_topic_id }

    scope :chronological, -> { order(:floor_number) }

    after_create :update_topic_counters

    def edit_body!(new_body, editor:)
      transaction do
        edits.create!(editor: editor, body_before: body, body_after: new_body)
        update!(body: new_body, edited_at: Time.current)
      end
    end

    private

    def update_topic_counters
      topic.update!(
        replies_count: topic.posts.count - 1,
        last_posted_at: created_at,
        last_post_user: user
      )
    end
  end
end
