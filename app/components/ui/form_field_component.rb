# frozen_string_literal: true

module Ui
  class FormFieldComponent < ApplicationComponent
    def initialize(form:, attribute:, label: nil, hint: nil, type: :text, required: false, html_options: {})
      @form = form
      @attribute = attribute
      @label = label
      @hint = hint
      @type = type.to_sym
      @required = required
      @html_options = html_options
    end

    private

    attr_reader :form, :attribute, :label, :hint, :type, :required, :html_options

    def field_label
      label || attribute.to_s.humanize
    end

    def errors
      form.object.errors[attribute]
    end

    def input_options
      opts = html_options.merge(class: [ "mc-input", html_options[:class] ].compact.join(" "))
      opts[:required] = true if required
      opts
    end

    def field_id
      "#{form.object_name}_#{attribute}"
    end
  end
end
