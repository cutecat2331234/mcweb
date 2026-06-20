# frozen_string_literal: true

module Community
  class SubscriptionLevelOptions
    LEVELS = %w[watching tracking normal off].freeze

    def self.for(context)
      prefix = context.to_sym == :section ? :section : (context.to_sym == :tag ? :tag : :topic)
      LEVELS.map do |value|
        {
          value: value,
          label: I18n.t("mcweb.forum.subscription_levels.#{value}"),
          description: I18n.t("mcweb.forum.subscription_levels.#{prefix}.#{value}_desc")
        }
      end
    end

    def self.guide
      SubscriptionLevelOptions.for(:topic)
    end
  end
end
