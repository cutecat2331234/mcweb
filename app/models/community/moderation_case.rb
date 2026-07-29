# frozen_string_literal: true

module Community
  class ModerationCase < ApplicationRecord
    self.table_name = "forum_moderation_cases"

    SOURCE_KINDS = %w[
      pending_topic pending_post report spam_hit quarantined_attachment user_risk
    ].freeze
    STATUSES = %w[open claimed resolved dismissed actioned stale].freeze
    PRIORITIES = %w[low normal high critical].freeze
    RISK_LEVELS = %w[low medium high critical].freeze
    ACTIVE_STATUSES = %w[open claimed].freeze

    belongs_to :source, polymorphic: true
    belongs_to :section,
      class_name: "Community::Section",
      foreign_key: :forum_section_id,
      optional: true
    belongs_to :target_user, class_name: "User", optional: true
    belongs_to :assignee, class_name: "User", optional: true
    has_many :notes,
      class_name: "Community::ModerationCaseNote",
      foreign_key: :moderation_case_id,
      dependent: :restrict_with_exception,
      inverse_of: :moderation_case

    enum :source_kind, SOURCE_KINDS.index_by(&:itself), validate: true, prefix: true
    enum :status, STATUSES.index_by(&:itself), validate: true, prefix: true
    enum :priority, PRIORITIES.index_by(&:itself), validate: true, prefix: true
    enum :risk_level, RISK_LEVELS.index_by(&:itself), validate: true, prefix: true

    validates :title, :source_updated_at, presence: true
    validates :title, length: { maximum: 255 }
    validates :summary, length: { maximum: 500 }
    validates :last_reason, length: { maximum: 1_000 }, allow_blank: true

    scope :active_queue, -> { where(status: ACTIVE_STATUSES) }
    scope :recent_first, -> {
      order(
        Arel.sql(
          "CASE priority WHEN 'critical' THEN 0 WHEN 'high' THEN 1 " \
          "WHEN 'normal' THEN 2 ELSE 3 END"
        ),
        source_updated_at: :desc,
        id: :desc
      )
    }
  end
end
