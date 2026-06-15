# frozen_string_literal: true

module Community
  class BatchTestSavedSearchWebhooks < ApplicationService
    LIMIT = 20

    def initialize(user:)
      @user = user
    end

    def call
      searches = @user.forum_saved_searches.recent.limit(LIMIT)
      return ServiceResult.failure(error: "没有可测试的保存搜索") if searches.empty?

      queued = 0
      searches.each do |search|
        result = Community::DispatchTestSavedSearchWebhook.call(saved_search: search)
        queued += 1 if result.success?
      end

      ServiceResult.success(queued: queued, total: searches.size)
    end
  end
end
