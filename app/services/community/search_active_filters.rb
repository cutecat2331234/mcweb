# frozen_string_literal: true

module Community
  class SearchActiveFilters
    VALUE_LABELS = SavedSearchFilterSummary::VALUE_LABELS

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

      items << chip(param: "q", label: "关键词：#{display_query}") if display_query.present?

      append_lookup_chip(items, :section, "分区") { Community::Section.find_by(slug: @filters[:section])&.name }
      append_lookup_chip(items, :category, "分类") { Community::Category.find_by(slug: @filters[:category])&.name }
      append_lookup_chip(items, :tag, "标签") { Community::Tag.find_by(slug: @filters[:tag])&.name }

      append_value_chip(items, :author, "作者")
      append_value_chip(items, :assignee, "负责人")
      append_value_chip(items, :created_after, "起始于")
      append_value_chip(items, :created_before, "截止于")

      VALUE_LABELS.each_key do |key|
        append_mapped_chip(items, key)
      end

      if parsed.success?
        parsed.value[:exclude_terms].each do |term|
          items << chip(param: "exclude", value: term, label: "排除：#{term}")
        end
      end

      items
    end

  private

    def chip(param:, label:, value: nil)
      { param: param.to_s, label: label, value: value }
    end

    def append_lookup_chip(items, key, prefix)
      value = @filters[key].presence
      return if value.blank?

      name = yield
      items << chip(param: key, label: "#{prefix}：#{name || value}", value: value.to_s)
    end

    def append_value_chip(items, key, prefix)
      value = @filters[key].presence
      return if value.blank?

      items << chip(param: key, label: "#{prefix}：#{value}", value: value.to_s)
    end

    def append_mapped_chip(items, key)
      value = @filters[key].presence
      return if value.blank?

      label = VALUE_LABELS[key]&.[](value.to_s) || value
      items << chip(param: key, label: label, value: value.to_s)
    end
  end
end
