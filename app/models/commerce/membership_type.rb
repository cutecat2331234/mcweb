# frozen_string_literal: true

module Commerce
  class MembershipType < ApplicationRecord
    self.table_name = "store_membership_types"

    has_many :user_memberships, class_name: "Commerce::UserMembership", foreign_key: :store_membership_type_id, dependent: :restrict_with_error
    has_many :products, class_name: "Commerce::Product", foreign_key: :store_membership_type_id, dependent: :nullify

    enum :duration_mode, { permanent: "permanent", fixed_days: "fixed_days" }, validate: true
    enum :game_permission_mode, { website_managed: "website_managed", lp_timed: "lp_timed" }, validate: true, prefix: :game_permission

    validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9\-_]+\z/ }
    validates :name, presence: true
    validates :duration_days, numericality: { only_integer: true, greater_than: 0 }, if: :fixed_days?
    validate :duration_days_absent_when_permanent

    scope :active_types, -> { where(active: true) }
    scope :by_display_priority, -> { order(display_priority: :desc, name: :asc) }

    def default_grant_commands
      group = luckperms_group.presence || slug
      if game_permission_lp_timed?
        duration = "#{duration_days}d"
        [ "lp user {player} parent addtemp #{group} #{duration}" ]
      else
        [ "lp user {player} parent add #{group}" ]
      end
    end

    def default_revoke_commands
      group = luckperms_group.presence || slug
      [ "lp user {player} parent remove #{group}" ]
    end

    def resolved_grant_commands
      Array(grant_commands).map(&:to_s).reject(&:blank?).presence || default_grant_commands
    end

    def resolved_revoke_commands
      Array(revoke_commands).map(&:to_s).reject(&:blank?).presence || default_revoke_commands
    end

    def duration_for_membership
      return nil if permanent?

      duration_days.days
    end

    private

    def duration_days_absent_when_permanent
      return unless permanent?
      return if duration_days.blank?

      errors.add(:duration_days, :blank_for_permanent) if duration_days.present?
    end
  end
end
