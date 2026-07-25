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
      @user = saved_search.respond_to?(:user) ? saved_search.user : nil
    end

    def labels
      chips = []
      query = @saved_search.query.to_s.strip
      chips << I18n.t("mcweb.forum.search.keywords", value: query) if query.present?

      append_lookup_label(chips, :section, "section") { visible_section_name(@filters[:section]) }
      append_lookup_label(chips, :category, "category") { visible_category_name(@filters[:category]) }
      append_lookup_label(chips, :tag, "tag") do
        Community::Tag.resolve_by_slug_for(@filters[:tag], user: @user)&.name
      end

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
