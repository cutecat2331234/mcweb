module Community
  class Report < ApplicationRecord
    REASONS = {
      "spam" => "垃圾广告 / 刷屏",
      "offensive" => "辱骂 / 不当内容",
      "off_topic" => "跑题 / 无关内容",
      "other" => "其他"
    }.freeze

    belongs_to :reporter, class_name: "User"
    belongs_to :reportable, polymorphic: true
    belongs_to :reviewer, class_name: "User", optional: true

    enum :status, { pending: "pending", reviewed: "reviewed", dismissed: "dismissed", actioned: "actioned" }, validate: true

    validates :reason, presence: true
    validates :reason_code, inclusion: { in: REASONS.keys }, allow_blank: true

    def reason_label
      REASONS[reason_code] || reason_code
    end

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
