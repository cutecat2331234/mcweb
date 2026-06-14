# frozen_string_literal: true

module Community
  class CensoredWord < ApplicationRecord
    validates :word, presence: true, uniqueness: { case_sensitive: false }
    validates :replacement, presence: true

    scope :ordered, -> { order(:word) }
  end
end
