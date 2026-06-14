module Community
  class Mute < ApplicationRecord
    belongs_to :user
    belongs_to :section, class_name: "Community::Section", foreign_key: :forum_section_id, optional: true
    belongs_to :created_by, class_name: "User"

    scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

    def active?
      expires_at.nil? || expires_at > Time.current
    end

    def self.muted?(user, section: nil)
      scope = active.where(user: user)
      scope = scope.where(forum_section_id: [ nil, section&.id ]) if section
      scope.exists?
    end
  end
end
