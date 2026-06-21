# frozen_string_literal: true

module Website
  class ResolveSeo < ApplicationService
    def initialize(record:, locale: I18n.locale)
      @record = record
      @locale = locale.to_s
    end

    def call
      base = (@record.seo || {}).with_indifferent_access
      trans = ((@record.translations || {})[@locale] || {}).with_indifferent_access
      trans_seo = (trans[:seo] || {}).with_indifferent_access

      ServiceResult.success(
        title: trans_seo[:title].presence || trans[:title].presence || base[:title].presence || @record.title,
        description: trans_seo[:description].presence || base[:description],
        og_image: trans_seo[:og_image].presence || base[:og_image]
      )
    end
  end
end
