# frozen_string_literal: true

module Community
  class SubscriptionLevelOptions
    TOPIC = [
      { value: "watching", label: "关注", description: "所有新回复通知，关注时可发邮件" },
      { value: "tracking", label: "跟踪", description: "所有新回复站内通知，不发邮件" },
      { value: "normal", label: "普通", description: "仅在你参与过或被 @提及时通知" },
      { value: "off", label: "关闭", description: "不接收此主题通知" }
    ].freeze

    SECTION = [
      { value: "watching", label: "关注", description: "分区内所有新主题通知，关注时可发邮件" },
      { value: "tracking", label: "跟踪", description: "分区内所有新主题站内通知" },
      { value: "normal", label: "普通", description: "不接收分区新主题通知" },
      { value: "off", label: "关闭", description: "取消关注此分区" }
    ].freeze

    TAG = [
      { value: "watching", label: "关注", description: "标签下所有新主题通知，关注时可发邮件" },
      { value: "tracking", label: "跟踪", description: "标签下所有新主题站内通知" },
      { value: "normal", label: "普通", description: "不接收标签新主题通知" },
      { value: "off", label: "关闭", description: "取消关注此标签" }
    ].freeze

    GUIDE = TOPIC.freeze

    def self.for(context)
      case context.to_sym
      when :section then SECTION
      when :tag then TAG
      else TOPIC
      end
    end
  end
end
