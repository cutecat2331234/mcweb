module Community
  class Report < ApplicationRecord
    belongs_to :reporter, class_name: "User"
    belongs_to :reportable, polymorphic: true
    belongs_to :reviewer, class_name: "User", optional: true

    enum :status, { pending: "pending", reviewed: "reviewed", dismissed: "dismissed", actioned: "actioned" }, validate: true

    validates :reason, presence: true

    scope :pending_review, -> { where(status: :pending) }

    def review!(reviewer:, note: nil, status: :reviewed)
      update!(
        reviewer: reviewer,
        review_note: note,
        reviewed_at: Time.current,
        status: status
      )
    end
  end
end
