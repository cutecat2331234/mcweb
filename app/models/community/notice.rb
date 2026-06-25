# frozen_string_literal: true

module Community
  # XenForo-style admin "Notices": dismissible banners shown to users, with simple
  # audience / trust-level display criteria.
  class Notice < ApplicationRecord
    self.table_name = "forum_notices"

    STYLES = %w[info success warning danger].freeze
    AUDIENCES = %w[everyone members guests].freeze

    validates :title, presence: true, length: { maximum: 120 }
    validates :message, presence: true
    validates :style, inclusion: { in: STYLES }
    validates :audience, inclusion: { in: AUDIENCES }
    validates :min_trust_level, :max_trust_level,
              numericality: { only_integer: true, in: 0..4 }, allow_nil: true

    scope :active, -> { where(active: true) }
    scope :ordered, -> { order(position: :asc, id: :asc) }

    def visible_to?(user)
      return false unless active?
      return false unless within_schedule?
      return false unless audience_matches?(user)

      trust_level_matches?(user)
    end

    private

    def within_schedule?
      now = Time.current
      return false if starts_at.present? && now < starts_at
      return false if ends_at.present? && now > ends_at

      true
    end

    def audience_matches?(user)
      case audience
      when "members" then user.present?
      when "guests" then user.nil?
      else true
      end
    end

    def trust_level_matches?(user)
      return min_trust_level.to_i.zero? if user.nil?
      return true if min_trust_level.nil? && max_trust_level.nil?

      level = Community::TrustLevel.level_for(user)
      return false if min_trust_level && level < min_trust_level
      return false if max_trust_level && level > max_trust_level

      true
    end
  end
end
