module Community
  class Report < ApplicationRecord
    REASONS = {
      "spam" => "垃圾广告 / 刷屏",
      "offensive" => "辱骂 / 不当内容",
      "off_topic" => "跑题 / 无关内容",
      "other" => "其他"
    }.freeze

    # Built-in reasons plus any admin-configured extras
    # (forum.extra_report_reasons = "code:Label,code2:Label2").
    def self.reason_options
      raw = SiteSetting.get("forum.extra_report_reasons", "").to_s
      extra = raw.split(",").each_with_object({}) do |pair, hash|
        code, label = pair.split(":", 2)
        hash[code.to_s.strip] = label.to_s.strip if code.to_s.strip.present? && label.to_s.strip.present?
      end
      REASONS.merge(extra)
    end

    belongs_to :reporter, class_name: "User"
    belongs_to :reportable, polymorphic: true
    belongs_to :reviewer, class_name: "User", optional: true

    enum :status, { pending: "pending", reviewed: "reviewed", dismissed: "dismissed", actioned: "actioned" }, validate: true

    validates :reason, presence: true
    validate :reason_code_allowed

    def reason_label
      self.class.reason_options[reason_code] || reason_code
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

    private

    def reason_code_allowed
      return if reason_code.blank?

      errors.add(:reason_code, :inclusion) unless self.class.reason_options.key?(reason_code)
    end
  end
end
