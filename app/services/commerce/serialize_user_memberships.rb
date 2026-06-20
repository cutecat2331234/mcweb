# frozen_string_literal: true

module Commerce
  class SerializeUserMemberships < ApplicationService
    def initialize(user:, limit: nil)
      @user = user
      @limit = limit
    end

    def call
      scope = Commerce::UserMembership
        .currently_active
        .includes(:membership_type)
        .joins(:membership_type)
        .merge(Commerce::MembershipType.by_display_priority)

      scope = scope.limit(@limit) if @limit.present?

      ServiceResult.success(scope.map { |membership| serialize(membership) })
    end

    def self.for_user(user, limit: nil)
      call(user: user, limit: limit).value || []
    end

    private

    def serialize(membership)
      type = membership.membership_type
      {
        slug: type.slug,
        name: type.name,
        color: type.color,
        icon: type.icon,
        expires_at: membership.expires_at&.iso8601,
        expires_label: expires_label(membership),
        permanent: membership.permanent?,
        label: type.name
      }
    end

    def expires_label(membership)
      return I18n.t("commerce.memberships.permanent") if membership.permanent?

      I18n.l(membership.expires_at, format: :short)
    end
  end
end
