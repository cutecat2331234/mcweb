# frozen_string_literal: true

module Community
  class ModerationCaseNote < ApplicationRecord
    self.table_name = "forum_moderation_case_notes"

    belongs_to :moderation_case,
      class_name: "Community::ModerationCase",
      inverse_of: :notes
    belongs_to :author, class_name: "User"

    before_update { throw(:abort) }
    before_destroy { throw(:abort) }

    validates :body, presence: true, length: { maximum: 2_000 }
  end
end
