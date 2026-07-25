# frozen_string_literal: true

module Community
  class SearchActiveFilters
    def self.call(filters = nil, user: nil, **filter_keywords)
      normalized_filters = filters&.to_h || {}
      normalized_filters = normalized_filters.merge(filter_keywords) if filter_keywords.any?

      new(normalized_filters, user: user).chips
    end

    def initialize(filters, user: nil)
      @filters = filters.symbolize_keys
      @user = user
    end

    def chips
      items = []
      query = @filters[:query].to_s.strip
      parsed = Community::ParseSearchQuery.call(query: query)
      display_query = parsed.success? ? parsed.value[:query].to_s.strip : query

      items << chip(param: "q", label: I18n.t("mcweb.forum.search.keywords", value: display_query), value: display_query) if display_query.present?

      append_lookup_chip(items, :section, "section") { visible_section_name(@filters[:section]) }
      append_lookup_chip(items, :category, "category") { visible_category_name(@filters[:category]) }
      append_lookup_chip(items, :tag, "tag") do
        Community::Tag.resolve_by_slug_for(@filters[:tag], user: @user)&.name
      end

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

    def visible_section_name(slug)
      section = Community::Section.find_by(slug: slug)
      section&.name if Community::SectionAccess.view?(section: section, user: @user)
    end

    def visible_category_name(slug)
      category = Community::Category.find_by(slug: slug)
      return unless category
      return category.name unless category.sections.exists?

      visible = Community::SectionAccess.scope(relation: category.sections, user: @user).exists?
      category.name if visible
    end

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
