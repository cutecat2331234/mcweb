# frozen_string_literal: true

module Community
  class TopicListActiveFilters
    def self.call(filter:, prefixes: [], staff: false)
      new(filter: filter, prefixes: prefixes, staff: staff).chips
    end

    def initialize(filter:, prefixes: [], staff: false)
      @filter = filter.to_s
      @prefixes = prefixes
      @staff = staff
    end

    def chips
      return [] if @filter.blank?

      label = filter_label
      return [] if label.blank?

      [ { param: "filter", label: label, value: @filter } ]
    end

  private

    def filter_label
      if (match = @filter.match(/\Aprefix:(.+)\z/))
        I18n.t("mcweb.forum.topic_filter.prefix", prefix: match[1])
      else
        I18n.t("mcweb.forum.topic_filter.#{@filter}", default: nil)
      end
    end
  end
end
