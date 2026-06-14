# frozen_string_literal: true

module Ui
  class BadgeComponent < ApplicationComponent
    VARIANTS = {
      default: "mc-badge",
      primary: "mc-badge mc-badge-primary",
      danger: "mc-badge mc-badge-danger",
      success: "mc-badge mc-badge-success"
    }.freeze

    def initialize(label:, variant: :default, html_options: {})
      @label = label
      @variant = variant.to_sym
      @html_options = html_options
    end

    private

    attr_reader :label, :variant, :html_options

    def css_class
      [ VARIANTS.fetch(variant, VARIANTS[:default]), html_options[:class] ].compact.join(" ")
    end
  end
end
