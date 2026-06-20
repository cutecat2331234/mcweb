# frozen_string_literal: true

module Community
  class SearchActiveFilters
    def self.call(filters)
      new(filters).chips
    end

    def initialize(filters)
      @filters = filters.symbolize_keys
    end

    def chips
      items = []
      query = @filters[:query].to_s.strip
      parsed = Community::ParseSearchQuery.call(query: query)
      display_query = parsed.success? ? parsed.value[:query].to_s.strip : query

      items << chip(param: "q", label: I18n.t("mcweb.forum.search.keywords", value: display_query), value: display_query) if display_query.present?

      append_lookup_chip(items, :section, "section") { Community::Section.find_by(slug: @filters[:section])&.name }
      append_lookup_chip(items, :category, "category") { Community::Category.find_by(slug: @filters[:category])&.name }
      append_lookup_chip(items, :tag, "tag") { Community::Tag.find_by(slug: @filters[:tag])&.name }

      append_value_chip(items, :author, "author")
      append_value_chip(items, :assignee, "assignee")
      append_value_chip(items, :created_after, "created_after")
      append_value_chip(items, :created_before, "created_before")

      SavedSearchFilterSummary::VALUE_KEYS.each do |key|
        append_mapped_chip(items, key)
      end

      if parsed.success?
        parsed.value[:exclude_terms].each do |term|
          items << chip(param: "exclude", value: term, label: I18n.t("mcweb.forum.search.exclude", value: term))
        end
      end

      items
    end

  private

    def chip(param:, label:, value: nil)
      { param: param.to_s, label: label, value: value }
    end

    def append_lookup_chip(items, key, prefix_key)
      value = @filters[key].presence
      return if value.blank?

      name = yield
      items << chip(param: key, label: I18n.t("mcweb.forum.search.#{prefix_key}", value: name || value), value: value.to_s)
    end

    def append_value_chip(items, key, prefix_key)
      value = @filters[key].presence
      return if value.blank?

      items << chip(param: key, label: I18n.t("mcweb.forum.search.#{prefix_key}", value: value), value: value.to_s)
    end

    def append_mapped_chip(items, key)
      value = @filters[key].presence
      return if value.blank?

      label = SavedSearchFilterSummary.value_label(key, value.to_s)
      items << chip(param: key, label: label, value: value.to_s)
    end
  end
end
