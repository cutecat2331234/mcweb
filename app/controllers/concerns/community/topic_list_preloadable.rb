# frozen_string_literal: true

module Community
  module TopicListPreloadable
    extend ActiveSupport::Concern

    TOPIC_LIST_INCLUDES = [ :user, :section, :last_post_user, :tags, :linked_product ].freeze

    private

    def preload_topics(scope)
      scope.includes(TOPIC_LIST_INCLUDES)
    end
  end
end
