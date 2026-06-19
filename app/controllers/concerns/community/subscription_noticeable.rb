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
      I18n.t("mcweb.flash.subscription.watching.#{context}")
    end

    def tracking_notice(context)
      I18n.t("mcweb.flash.subscription.tracking.#{context}")
    end

    def normal_notice(context)
      I18n.t("mcweb.flash.subscription.normal.#{context}")
    end

    def off_notice(context)
      I18n.t("mcweb.flash.subscription.off.#{context}")
    end

    def redirect_after_subscription_update(fallback_location:, notice: nil, alert: nil)
      options = { fallback_location: fallback_location }
      options[:notice] = notice if notice
      options[:alert] = alert if alert
      redirect_back **options
    end
  end
end
