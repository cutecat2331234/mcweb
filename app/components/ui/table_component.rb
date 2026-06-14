# frozen_string_literal: true

module Ui
  class TableComponent < ApplicationComponent
    renders_many :columns, "ColumnComponent"
    renders_many :rows, "RowComponent"

    def initialize(striped: true, html_options: {})
      @striped = striped
      @html_options = html_options
    end

    class ColumnComponent < ViewComponent::Base
      def initialize(label:, align: "left")
        @label = label
        @align = align
      end

      attr_reader :label, :align
    end

    class RowComponent < ViewComponent::Base
      renders_many :cells, "CellComponent"

      class CellComponent < ViewComponent::Base
        def initialize(align: "left")
          @align = align
        end

        attr_reader :align
      end
    end

    private

    attr_reader :striped, :html_options

    def css_class
      [ "mc-table", html_options[:class] ].compact.join(" ")
    end
  end
end
