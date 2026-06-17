# frozen_string_literal: true

module Community
  class CheckWarningRestrictions < ApplicationService
    ACTIONS = %i[post link pm].freeze

    def initialize(user:, action:)
      @user = user
      @action = action.to_sym
    end

    def call
      return ServiceResult.success unless ACTIONS.include?(@action)

      total = Community::UserWarning.total_points_for(@user)
      threshold = threshold_for(@action)
      return ServiceResult.success if threshold <= 0
      return ServiceResult.success if total < threshold

      ServiceResult.failure(error: restriction_message(@action, total, threshold))
    end

    private

    def threshold_for(action)
      key = case action
            when :post then "forum.warning_block_post_threshold"
            when :link then "forum.warning_block_links_threshold"
            when :pm then "forum.warning_block_pm_threshold"
            end
      SiteSetting.get(key, "0").to_i
    end

    def restriction_message(action, total, threshold)
      case action
      when :post
        "警告积分 #{total} 点已达限制阈值（#{threshold}），暂时无法发帖。"
      when :link
        "警告积分 #{total} 点已达限制阈值（#{threshold}），暂时无法发布链接。"
      when :pm
        "警告积分 #{total} 点已达限制阈值（#{threshold}），暂时无法发送私信。"
      end
    end
  end
end
