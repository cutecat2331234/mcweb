# frozen_string_literal: true

module Ui
  class ButtonComponent < ApplicationComponent
    VARIANTS = {
      default: "mc-btn",
      primary: "mc-btn mc-btn-primary",
      danger: "mc-btn mc-btn-danger"
    }.freeze

    def initialize(label:, variant: :default, type: "button", href: nil, method: nil, disabled: false, html_options: {})
      @label = label
      @variant = variant.to_sym
      @type = type
      @href = href
      @method = method
      @disabled = disabled
      @html_options = html_options
    end

    private

    attr_reader :label, :variant, :type, :href, :method, :disabled, :html_options

    def css_class
      [ VARIANTS.fetch(variant, VARIANTS[:default]), html_options[:class] ].compact.join(" ")
    end

    def tag_options
      html_options.except(:class).merge(class: css_class, disabled: disabled)
    end

    def link?
      href.present?
    end
  end
end
