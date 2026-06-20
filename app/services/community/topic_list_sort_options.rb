# frozen_string_literal: true

module Community
  class TopicListSortOptions
    DEFAULT_SORTS = %w[latest hot replies newest].freeze
    UNREAD_SORTS = (DEFAULT_SORTS + %w[unread]).freeze

    def self.call(include_unread: false)
      sorts = include_unread ? UNREAD_SORTS : DEFAULT_SORTS
      sorts.map { |value| { value: value, label: I18n.t("mcweb.forum.topic_sort.#{value}") } }
    end
  end
end
