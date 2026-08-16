# frozen_string_literal: true

module CanonicalPagination
  extend ActiveSupport::Concern

  class PageOutOfRange < StandardError
    def initialize(page_key:, last_page:)
      @page_key = page_key.to_s
      @last_page = last_page
      super("pagination page exceeds the available range")
    end

    attr_reader :page_key, :last_page
  end

  included do
    rescue_from PageOutOfRange, with: :redirect_to_canonical_page
  end

  def pagy(paginator = :offset, collection, **options)
    pagination, records = super
    return [ pagination, records ] unless canonical_offset_page_required?(pagination, options)

    raise PageOutOfRange.new(
      page_key: options.fetch(:page_key, "page"),
      last_page: pagination.pages
    )
  end

  private

  def canonical_offset_page_required?(pagination, options)
    return false unless pagination.is_a?(Pagy::Offset)
    return false if options.key?(:page) && !options.key?(:page_key)

    pagination.page > pagination.pages
  end

  def redirect_to_canonical_page(error)
    query = request.query_parameters.merge(error.page_key => error.last_page.to_s)
    location = request.path
    location = "#{location}?#{query.to_query}" if query.present?
    redirect_to location, status: :found
  end
end
