# frozen_string_literal: true

module Administration
  # XenForo-style email ban / filter. `pattern` is an exact email or a wildcard
  # using `*` (e.g. "*@spam.com", "bad@*", "spammer*@*"). Matching is case-insensitive.
  class EmailBan < ApplicationRecord
    belongs_to :banned_by, class_name: "User", optional: true

    validates :pattern, presence: true, uniqueness: { case_sensitive: false }

    scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

    def active?
      expires_at.nil? || expires_at > Time.current
    end

    def matches?(email)
      self.class.pattern_to_regex(pattern).match?(email.to_s.strip)
    end

    # Does any active ban match the given email?
    def self.match?(email)
      normalized = email.to_s.strip
      return false if normalized.blank?

      active.any? { |ban| ban.matches?(normalized) }
    end

    def self.pattern_to_regex(pattern)
      escaped = Regexp.escape(pattern.to_s.strip).gsub('\\*', ".*")
      /\A#{escaped}\z/i
    end
  end
end
