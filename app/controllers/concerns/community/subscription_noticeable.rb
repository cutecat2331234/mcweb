# frozen_string_literal: true

module Community
  module SubscriptionNoticeable
    extend ActiveSupport::Concern

  private

    def subscription_notice(watching, notification_level, context:)
      return off_notice(context) unless watching

      case notification_level
      when "tracking" then tracking_notice(context)
      when "normal" then normal_notice(context)
      else watching_notice(context)
      end
    end

    def watching_notice(context)
      {
        topic: "已关注此主题（即时通知）。",
        section: "已关注此分区（即时通知）。",
        tag: "已关注此标签（即时通知）。"
      }[context]
    end

    def tracking_notice(context)
      {
        topic: "已切换为跟踪此主题（仅站内通知）。",
        section: "已切换为跟踪此分区（仅站内通知）。",
        tag: "已切换为跟踪此标签（仅站内通知）。"
      }[context]
    end

    def normal_notice(context)
      {
        topic: "已切换为普通（仅参与或被 @提及时通知）。",
        section: "已切换为普通（不接收分区新主题通知）。",
        tag: "已切换为普通（不接收标签新主题通知）。"
      }[context]
    end

    def off_notice(context)
      {
        topic: "已关闭此主题通知。",
        section: "已取消关注此分区。",
        tag: "已取消关注此标签。"
      }[context]
    end

    def redirect_after_subscription_update(fallback_location:, notice: nil, alert: nil)
      options = { fallback_location: fallback_location }
      options[:notice] = notice if notice
      options[:alert] = alert if alert
      redirect_back **options
    end
  end
end
