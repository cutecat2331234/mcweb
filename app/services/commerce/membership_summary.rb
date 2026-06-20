# frozen_string_literal: true

module Commerce
  class MembershipSummary
    class << self
      def for_user(user)
        memberships = SerializeUserMemberships.for_user(user)
        labels = memberships.map { |m| m[:name] }.join(", ")
        primary = memberships.first&.dig(:name).to_s
        expires_at = nearest_expiry_label(memberships)

        {
          memberships: memberships,
          membership_labels: labels,
          membership_primary: primary,
          membership_expires_at: expires_at
        }
      end

      private

      def nearest_expiry_label(memberships)
        dated = memberships.reject { |m| m[:permanent] }
        return I18n.t("commerce.memberships.permanent") if dated.empty?

        nearest = dated.min_by { |m| Time.zone.parse(m[:expires_at].to_s) }
        nearest[:expires_label]
      rescue ArgumentError, TypeError
        ""
      end
    end
  end
end
