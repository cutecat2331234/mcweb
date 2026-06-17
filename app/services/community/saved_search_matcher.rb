# frozen_string_literal: true

module Community
  class SavedSearchMatcher
    def initialize(saved_search)
      @saved_search = saved_search
    end

    def matching_topics(since: nil)
      result = Community::BuildSavedSearchTopicScope.call(saved_search: @saved_search, since: since)
      result.success? ? result.value : Community::Topic.none
    end
  end
end
