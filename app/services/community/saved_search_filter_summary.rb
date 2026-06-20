# frozen_string_literal: true

module Community
  class SavedSearchFilterSummary
    VALUE_KEYS = %i[
      solved locked pinned wiki featured announcement assigned unlisted archived mine
      scope poll noreplies images topic_sort post_sort title_only posts_only
    ].freeze

    def self.call(saved_search)
      new(saved_search).labels
    end

    def self.value_label(key, value)
      I18n.t("mcweb.forum.saved_search.values.#{key}.#{value}", default: value.to_s)
    end

    def initialize(saved_search)
      @saved_search = saved_search
      @filters = saved_search.filters.symbolize_keys
    end

    def labels
      chips = []
      query = @saved_search.query.to_s.strip
      chips << I18n.t("mcweb.forum.search.keywords", value: query) if query.present?

      append_lookup_label(chips, :section, "section") { Community::Section.find_by(slug: @filters[:section])&.name }
      append_lookup_label(chips, :category, "category") { Community::Category.find_by(slug: @filters[:category])&.name }
      append_lookup_label(chips, :tag, "tag") { Community::Tag.find_by(slug: @filters[:tag])&.name }

      append_value_label(chips, :author, "author")
      append_value_label(chips, :assignee, "assignee")
      append_value_label(chips, :created_after, "created_after")
      append_value_label(chips, :created_before, "created_before")

      VALUE_KEYS.each do |key|
        append_mapped_label(chips, key)
      end

      append_exclude_terms(chips)

      chips
    end

  private

    def append_exclude_terms(chips)
      parsed = Community::ParseSearchQuery.call(query: @saved_search.query.to_s)
      return unless parsed.success?

      parsed.value[:exclude_terms].each do |term|
        chips << I18n.t("mcweb.forum.search.exclude", value: term)
      end
    end

    def append_lookup_label(chips, key, prefix_key)
      value = @filters[key].presence
      return if value.blank?

      name = yield
      chips << I18n.t("mcweb.forum.search.#{prefix_key}", value: name || value)
    end

    def append_value_label(chips, key, prefix_key)
      value = @filters[key].presence
      return if value.blank?

      chips << I18n.t("mcweb.forum.search.#{prefix_key}", value: value)
    end

    def append_mapped_label(chips, key)
      value = @filters[key].presence
      return if value.blank?

      label = self.class.value_label(key, value.to_s)
      chips << label
    end
  end
end
