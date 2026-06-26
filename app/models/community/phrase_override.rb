# frozen_string_literal: true

module Community
  # A DB-backed translation override (XenForo "phrases"). Server-side I18n looks
  # these up via a Chain backend; the full map is cached to avoid a query per
  # `t` call, and the cache is rebuilt on any change.
  class PhraseOverride < ApplicationRecord
    self.table_name = "community_phrase_overrides"

    validates :locale, presence: true
    validates :key, presence: true, uniqueness: { scope: :locale }

    scope :ordered, -> { order(:locale, :key) }

    # { "en" => { "some.key" => "value", ... }, "zh-CN" => {...} }. Loaded
    # directly from the DB (the I18n backend memoizes this in-process with a
    # short TTL, so this is not called per-translation).
    def self.map
      all.group_by(&:locale).transform_values { |rows| rows.to_h { |row| [ row.key, row.value ] } }
    rescue StandardError
      {}
    end
  end
end
