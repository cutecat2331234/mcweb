# frozen_string_literal: true

module DataGovernance
  class RetentionHold < ApplicationRecord
    self.table_name = "data_retention_holds"

    include HasPublicId

    belongs_to :target, polymorphic: true
    belongs_to :created_by, class_name: "User"
    belongs_to :released_by, class_name: "User", optional: true

    enum :status, { active: "active", released: "released" }, validate: true

    validates :reason, presence: true, length: { maximum: 2_000 }
    validates :release_reason, presence: true, if: :released?

    scope :effective, -> {
      active.where("expires_at IS NULL OR expires_at > ?", Time.current)
    }

    def effective?
      active? && (expires_at.nil? || expires_at.future?)
    end

    def resolved_target
      if ContentRegistry.supported?(target_type)
        ContentRegistry.resolve(target_type:, target_id:)
      else
        target
      end
    end
  end
end
