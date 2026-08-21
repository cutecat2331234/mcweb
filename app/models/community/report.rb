module Community
  class Report < ApplicationRecord
    REASON_CODES = %w[spam offensive off_topic other].freeze
    MAX_REASON_LENGTH = 2_000

    # Built-in reasons plus any admin-configured extras
    # (forum.extra_report_reasons = "code:Label,code2:Label2").
    def self.reason_options(locale: I18n.locale)
      built_in = REASON_CODES.index_with do |code|
        I18n.t("mcweb.forum.reports.reasons.#{code}", locale: locale)
      end
      raw = SiteSetting.get("forum.extra_report_reasons", "").to_s
      extra = raw.split(",").each_with_object({}) do |pair, hash|
        code, label = pair.split(":", 2)
        hash[code.to_s.strip] = label.to_s.strip if code.to_s.strip.present? && label.to_s.strip.present?
      end
      built_in.merge(extra)
    end

    belongs_to :reporter, class_name: "User"
    belongs_to :reportable, polymorphic: true
    belongs_to :reviewer, class_name: "User", optional: true
    has_one :evidence,
      class_name: "Community::ReportEvidence",
      foreign_key: :forum_report_id,
      inverse_of: :report,
      dependent: :restrict_with_error

    enum :status, { pending: "pending", reviewed: "reviewed", dismissed: "dismissed", actioned: "actioned" }, validate: true

    validates :reason, presence: true
    validates :reason, length: { maximum: MAX_REASON_LENGTH }, on: :create
    validates :dedupe_key, format: { with: /\A[0-9a-f]{64}\z/ }, allow_nil: true
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
