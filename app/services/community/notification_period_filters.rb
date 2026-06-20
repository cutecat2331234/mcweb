# frozen_string_literal: true

module Community
  class NotificationPeriodFilters
    PERIODS = %w[today this_week this_month last_month last_year].freeze

    def self.call(user:, category: nil, read: nil, type: nil, active_period: nil)
      new(user: user, category: category, read: read, type: type, active_period: active_period).filters
    end

    def initialize(user:, category:, read:, type:, active_period:)
      @user = user
      @category = category.to_s
      @read = read.to_s
      @type = type.to_s
      @active_period = active_period.to_s
    end

    def filters
      scope = base_scope

      PERIODS.filter_map do |period|
        count = count_for(scope, period)
        next if count.zero?

        {
          key: period,
          label: I18n.t("mcweb.forum.notifications.periods.#{period}"),
          period: period,
          href: Rails.application.routes.url_helpers.forum_notifications_path(tab_params(period)),
          active: @active_period == period,
          count: count
        }
      end
    end

  private

    def base_scope
      scope = @user.notifications
      scope = apply_category(scope)
      scope = scope.unread if @read == "unread"
      scope = scope.where(notification_type: @type) if @type.present?
      scope
    end

    def count_for(scope, period)
      NotificationPeriodScope.call(scope, period).count
    end

    def apply_category(scope)
      case @category
      when "forum"
        scope.where("notification_type NOT LIKE ?", "commerce.%")
      when "commerce"
        scope.where("notification_type LIKE ?", "commerce.%")
      else
        scope
      end
    end

    def tab_params(period)
      {
        category: @category.presence,
        read: @read == "unread" ? "unread" : nil,
        type: @type.presence,
        period: period
      }.compact
    end
  end
end
