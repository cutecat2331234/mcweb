# frozen_string_literal: true

module Community
  class DiffLines < ApplicationService
    def initialize(before_text:, after_text:)
      @before_lines = before_text.to_s.split("\n")
      @after_lines = after_text.to_s.split("\n")
    end

    def call
      ServiceResult.success(compute_diff)
    end

    private

    def compute_diff
      before_set = @before_lines
      after_set = @after_lines
      result = []

      before_set.each do |line|
        if after_set.include?(line)
          result << { kind: "same", text: line }
        else
          result << { kind: "removed", text: line }
        end
      end

      after_set.each do |line|
        result << { kind: "added", text: line } unless before_set.include?(line)
      end

      result
    end
  end
end
