module Community
  class Report < ApplicationRecord
    REASON_CODES = %w[spam offensive off_topic other].freeze
    STATUSES = %w[pending withdrawn reviewed dismissed actioned].freeze
    STAFF_FINAL_STATUSES = %w[reviewed dismissed actioned].freeze
    PUBLIC_OUTCOME_BY_STATUS = {
      "withdrawn" => "withdrawn",
      "reviewed" => "review_complete",
      "dismissed" => "not_upheld",
      "actioned" => "action_taken"
    }.freeze
    PUBLIC_OUTCOME_CODES = PUBLIC_OUTCOME_BY_STATUS.values.freeze
    STAFF_PUBLIC_OUTCOME_CODES = STAFF_FINAL_STATUSES.map { |status| PUBLIC_OUTCOME_BY_STATUS.fetch(status) }.freeze
    # Public compatibility contract retained for plugins and older callers.
    # New user-facing code must use reason_options so labels follow the active
    # locale instead of treating these historical Chinese values as UI copy.
    REASONS = {
      "spam" => "垃圾广告 / 刷屏",
      "offensive" => "辱骂 / 不当内容",
      "off_topic" => "跑题 / 无关内容",
      "other" => "其他"
    }.freeze
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
    has_many :supplements,
      class_name: "Community::ReportSupplement",
      foreign_key: :forum_report_id,
      inverse_of: :report,
      dependent: :restrict_with_error
    has_one :outcome_delivery,
      class_name: "Community::ReportOutcomeDelivery",
      foreign_key: :forum_report_id,
      inverse_of: :report,
      dependent: :restrict_with_error

    enum :status, STATUSES.index_with(&:itself), validate: true

    validates :reason, presence: true
    validates :reason, length: { maximum: MAX_REASON_LENGTH }, on: :create
    validates :dedupe_key, format: { with: /\A[0-9a-f]{64}\z/ }, allow_nil: true
    validates :withdrawal_idempotency_key_digest,
      format: { with: /\A[0-9a-f]{64}\z/ },
      allow_nil: true
    validates :public_outcome_code, inclusion: { in: PUBLIC_OUTCOME_CODES }, allow_nil: true
    validate :reason_code_allowed
    validate :terminal_state_not_reopened, on: :update
    validate :public_outcome_matches_status

    before_validation :normalize_lifecycle_fields

    def reason_label
      self.class.reason_options[reason_code] || reason_code
    end

    scope :pending_review, -> { where(status: :pending) }

    def self.public_outcome_for(status)
      PUBLIC_OUTCOME_BY_STATUS[status.to_s]
    end

    private

    def normalize_lifecycle_fields
      return if status.blank?

      if new_record? || will_save_change_to_status?
        self.state_changed_at = reviewed_at || withdrawn_at || Time.current
        self.public_outcome_code = self.class.public_outcome_for(status)
        self.withdrawn_at = state_changed_at if status == "withdrawn"
        self.withdrawn_at = nil unless status == "withdrawn"
      else
        self.state_changed_at ||= reviewed_at || created_at || Time.current
      end
    end

    def terminal_state_not_reopened
      return unless will_save_change_to_status?

      previous_status = status_change_to_be_saved.first
      return if previous_status == "pending"

      errors.add(:status, :invalid)
    end

    def public_outcome_matches_status
      expected = self.class.public_outcome_for(status)
      return if public_outcome_code == expected

      errors.add(:public_outcome_code, :invalid)
    end

    def reason_code_allowed
      return if reason_code.blank?

      errors.add(:reason_code, :inclusion) unless self.class.reason_options.key?(reason_code)
    end
  end
end
