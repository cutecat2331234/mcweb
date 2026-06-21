# frozen_string_literal: true

module Admin
  module Website
    module NestedLocaleParams
      extend ActiveSupport::Concern

      private

      def merge_nested_translations!(permitted, root_key)
        raw = params.dig(root_key, :translations)
        return if raw.blank?

        permitted[:translations] = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
      end
    end
  end
end
