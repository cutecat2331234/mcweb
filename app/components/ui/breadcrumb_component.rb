# frozen_string_literal: true

module Ui
  class BreadcrumbComponent < ApplicationComponent
    Item = Data.define(:label, :href, :current?)

    def initialize(items:)
      @items = items.map { |item| normalize_item(item) }
    end

    private

    attr_reader :items

    def normalize_item(item)
      case item
      when Item then item
      when Hash
        Item.new(
          label: item[:label] || item["label"],
          href: item[:href] || item["href"],
          current?: item[:current] || item["current"] || false
        )
      else
        raise ArgumentError, "Expected Hash or Item, got #{item.class}"
      end
    end
  end
end
