# frozen_string_literal: true

module Community
  class SearchRankOrder
    class << self
      def descending(table:, column:, query:)
        language = Arel::Nodes.build_quoted("simple")
        value = Arel::Nodes::NamedFunction.new(
          "coalesce",
          [ table[column], Arel::Nodes.build_quoted("") ]
        )
        vector = Arel::Nodes::NamedFunction.new("to_tsvector", [ language, value ])
        terms = Arel::Nodes::NamedFunction.new(
          "plainto_tsquery",
          [ language, Arel::Nodes.build_quoted(query.to_s) ]
        )
        rank = Arel::Nodes::NamedFunction.new("ts_rank", [ vector, terms ])

        Arel::Nodes::Descending.new(rank)
      end
    end
  end
end
