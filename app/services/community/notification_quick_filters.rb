# frozen_string_literal: true

module Community
  class NotificationQuickFilters
    FILTERS = [
      { key: "mention", label: "@提及", type: "forum.mention" },
      { key: "reply", label: "主题回复", type: "forum.topic_reply" },
      { key: "reaction", label: "帖子反应", type: "forum.reaction" },
      { key: "payment", label: "支付确认", type: "commerce.payment_confirmed" }
    ].freeze

    def self.call(user:, category: nil, read: nil, active_type: nil, period: nil)
      new(user: user, category: category, read: read, active_type: active_type, period: period).filters
    end

    def initialize(user:, category:, read:, active_type:, period: nil)
      @user = user
      @category = category.to_s
      @read = read.to_s
      @active_type = active_type.to_s
      @period = period.to_s
    end

    def filters
      scope = @user.notifications
      scope = apply_category(scope)
      scope = scope.unread if @read == "unread"
      scope = Community::NotificationPeriodScope.call(scope, @period) if @period.present?

      counts = scope.unscope(:order).group(:notification_type).count
      unread_counts = scope.unread.unscope(:order).group(:notification_type).count

      FILTERS.filter_map do |filter|
        count = counts[filter[:type]].to_i
        next if count.zero?

        {
          key: filter[:key],
          label: filter[:label],
          type: filter[:type],
          href: Rails.application.routes.url_helpers.forum_notifications_path(tab_params(filter[:type])),
          active: @active_type == filter[:type],
          count: count,
          unread_count: unread_counts[filter[:type]].to_i
        }
      end
    end

  private

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

    def tab_params(type)
      {
        category: @category.presence,
        read: @read == "unread" ? "unread" : nil,
        type: type,
        period: @period.presence
      }.compact
    end
  end
end
