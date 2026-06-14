# frozen_string_literal: true

require "diff/lcs"

module Community
  class DiffLines < ApplicationService
    def initialize(before_text:, after_text:)
      @before_lines = before_text.to_s.split("\n", -1)
      @after_lines = after_text.to_s.split("\n", -1)
      # Trim trailing empty line from split behavior when text doesn't end with newline
      @before_lines.pop if @before_lines.last == "" && !before_text.to_s.end_with?("\n")
      @after_lines.pop if @after_lines.last == "" && !after_text.to_s.end_with?("\n")
    end

    def call
      ServiceResult.success(compute_diff)
    end

    private

    def compute_diff
      Diff::LCS.sdiff(@before_lines, @after_lines).filter_map do |change|
        case change.action
        when "-"
          { kind: "removed", text: change.old_element }
        when "+"
          { kind: "added", text: change.new_element }
        when "="
          { kind: "same", text: change.old_element }
        when "!"
          [
            { kind: "removed", text: change.old_element },
            { kind: "added", text: change.new_element }
          ]
        end
      end.flatten
    end
  end
end
