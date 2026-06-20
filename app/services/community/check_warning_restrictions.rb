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
      key = case action
      when :post then "block_post"
      when :link then "block_links"
      when :pm then "block_pm"
      end
      I18n.t("mcweb.forum.warning_restrictions.#{key}", total: total, threshold: threshold)
    end
  end
end
