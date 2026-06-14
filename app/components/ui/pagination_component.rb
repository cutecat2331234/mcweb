# frozen_string_literal: true

module Ui
  class PaginationComponent < ApplicationComponent
    def initialize(pagy:)
      @pagy = pagy
    end

    private

    attr_reader :pagy

    def render?
      pagy.pages > 1
    end
  end
end
