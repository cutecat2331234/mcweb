# frozen_string_literal: true

module Ui
  class PageHeaderComponent < ApplicationComponent
    renders_one :actions

    def initialize(title:, subtitle: nil)
      @title = title
      @subtitle = subtitle
    end

    private

    attr_reader :title, :subtitle
  end
end
