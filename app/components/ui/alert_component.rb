# frozen_string_literal: true

module Ui
  class AlertComponent < ApplicationComponent
    VARIANTS = {
      info: "mc-alert mc-alert-info",
      success: "mc-alert mc-alert-success",
      warning: "mc-alert mc-alert-warning",
      danger: "mc-alert mc-alert-danger"
    }.freeze

    def initialize(message: nil, variant: :info, dismissible: false, html_options: {})
      @message = message
      @variant = variant.to_sym
      @dismissible = dismissible
      @html_options = html_options
    end

    private

    attr_reader :message, :variant, :dismissible, :html_options

    def css_class
      [ VARIANTS.fetch(variant, VARIANTS[:info]), html_options[:class] ].compact.join(" ")
    end

    def tag_options
      html_options.except(:class).merge(
        class: css_class,
        role: "alert"
      )
    end
  end
end
