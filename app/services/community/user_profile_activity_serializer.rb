# frozen_string_literal: true

module Community
  # The single serialization boundary for profile activity that may be shown
  # to the account owner, an explicitly authorized viewer, or the public after
  # the subject has opted in. Keep private-only account details outside this
  # class so the opt-in cannot accidentally broaden their visibility.
  class UserProfileActivitySerializer
    COMPLETED_ORDER_STATUSES = %w[paid processing fulfilling fulfilled completed].freeze

    attr_reader :visibility

    def initialize(user:, viewer:)
      @user = user
      @visibility = Community::UserProfileVisibility.new(user: user, viewer: viewer)
    end

    def visible?
      visibility.activity_summary?
    end

    def card
      return {} unless visible?

      ingame = Minecraft::IngameStatusForUser.call(user: @user)
      ingame_data = ingame.success? ? ingame.value : {}

      presence.merge(
        ingame_online: ingame_data[:ingame_online] == true,
        ingame_server: ingame_data[:ingame_server]
      )
    end

    def profile
      return {} unless visible?

      latest_check_in = Community::CheckIn.where(user: @user).order(checked_on: :desc).first
      payload = {
        forum_points: Community::PointAccount.find_by(user: @user, currency: "points")&.balance.to_i,
        check_in_streak: current_check_in_streak(latest_check_in),
        check_in_total: Community::CheckIn.where(user: @user).count,
        **presence,
        orders_count: Commerce::Order.where(user: @user, status: COMPLETED_ORDER_STATUSES).count
      }
      if visibility.private_activity?
        payload[:recent_point_transactions] = serialize_point_transactions
      end
      payload
    end

    def member(purchases_count:)
      return {} unless visible?

      presence.merge(purchases_count: purchases_count.to_i)
    end

    def minecraft(identity:)
      return {} unless visible?

      {
        last_seen_ingame_at: identity.last_seen_ingame_at&.then { |time| I18n.l(time, format: :short) }
      }
    end

    private

    def presence
      {
        last_seen_at: @user.last_seen_at&.then { |time| I18n.l(time, format: :short) },
        online: @user.last_seen_at.present? && @user.last_seen_at > 5.minutes.ago
      }
    end

    def serialize_point_transactions
      Community::PointTransaction
        .where(user: @user, currency: "points")
        .order(created_at: :desc)
        .limit(8)
        .map do |transaction|
          {
            amount: transaction.amount,
            reason: I18n.t("mcweb.forum.points.reasons.#{transaction.reason}", default: transaction.reason),
            balance_after: transaction.balance_after,
            created_at: I18n.l(transaction.created_at, format: :short)
          }
        end
    end

    def current_check_in_streak(latest_check_in)
      return 0 unless latest_check_in&.checked_on && latest_check_in.checked_on >= Date.current - 1

      latest_check_in.streak.to_i
    end
  end
end
