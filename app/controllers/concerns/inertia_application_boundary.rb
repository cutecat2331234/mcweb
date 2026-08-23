# frozen_string_literal: true

require "uri"

module InertiaApplicationBoundary
  extend ActiveSupport::Concern

  APPLICATION_HEADER = "X-McWeb-Application"
  VARY_HEADERS = ["X-Inertia", APPLICATION_HEADER].freeze

  included do
    prepend_before_action :resolve_and_enforce_inertia_application_boundary
    if respond_to?(:helper_method)
      helper_method :frontend_application_id,
        :frontend_application_entrypoint,
        :frontend_application_runtime_kind
    end
  end

  def render(*args, **options, &block)
    component = inertia_component_from_render_arguments(args, options)
    validate_inertia_component_boundary!(component) if component
    super
  end

  private

  def resolve_and_enforce_inertia_application_boundary
    registry = frontend_application_registry
    @frontend_route_match = registry.resolve(
      path: request.path,
      method: request.request_method
    )
    @frontend_application = @frontend_route_match&.application
    response.set_header(APPLICATION_HEADER, @frontend_application.id) if @frontend_application

    unless request.inertia?
      enforce_non_inertia_source_contract!
      return
    end

    merge_frontend_boundary_vary!
    unless @frontend_route_match
      return reject_inertia_application_request!(document_location: request.get?)
    end

    case @frontend_route_match.kind
    when "inertia_page"
      request.get? ? enforce_owned_inertia_request! :
        reject_inertia_application_request!(document_location: false)
    when "application_action"
      enforce_owned_inertia_request!(document_location: false)
    when "document", "download", "api"
      reject_inertia_application_request!(document_location: request.get?)
    when "shared_action"
      # Shared actions deliberately use a CSRF-protected fetch or native form.
      # An Inertia mutation must not be replayed or converted into navigation.
      reject_inertia_application_request!(document_location: false)
    else
      reject_inertia_application_request!(document_location: request.get?)
    end
  end

  def enforce_non_inertia_source_contract!
    return unless @frontend_route_match

    if @frontend_route_match.kind == "shared_action"
      source_id = referer_application_id
      allowed = source_id.present? && application_header_consistent_with?(source_id) &&
        frontend_application_registry.source_allowed?(
        @frontend_route_match,
        source_id
      )
      reject_inertia_application_request!(document_location: false) unless allowed
      return
    end

    return unless @frontend_route_match.kind == "application_action"

    source_id = referer_application_id
    return if source_id == @frontend_application&.id && application_header_consistent_with?(source_id) &&
      frontend_application_registry.application(source_id)

    reject_inertia_application_request!(document_location: false)
  end

  def referer_application_id
    referer_path = same_origin_referer_path
    return unless referer_path

    frontend_application_registry.resolve(path: referer_path, method: "GET")&.application_id
  end

  def application_header_consistent_with?(source_id)
    explicit = request.headers[APPLICATION_HEADER].to_s
    explicit.blank? || explicit == source_id
  end

  def same_origin_referer_path
    referer = request.referer.to_s
    return if referer.blank?

    uri = URI.parse(referer)
    request_uri = URI.parse(request.base_url)
    return unless uri.scheme == request_uri.scheme && uri.host == request_uri.host && uri.port == request_uri.port

    uri.path.presence || "/"
  rescue URI::InvalidURIError
    nil
  end

  def enforce_owned_inertia_request!(document_location: request.get?)
    source_id = referer_application_id
    explicit_id = request.headers[APPLICATION_HEADER].to_s
    target_id = @frontend_application&.id
    return if source_id.present? && source_id == target_id && explicit_id == source_id &&
      frontend_application_registry.application(source_id)

    reject_inertia_application_request!(document_location:)
  end

  def reject_inertia_application_request!(document_location:)
    flash.keep if respond_to?(:flash)
    response.cache_control[:no_store] = true
    merge_frontend_boundary_vary!
    if document_location
      response.set_header("X-Inertia-Location", validated_original_document_path)
      response.headers.delete("X-McWeb-Safe-Location")
    else
      response.headers.delete("X-Inertia-Location")
      safe_location = frontend_boundary_safe_get_path
      response.set_header("X-McWeb-Safe-Location", safe_location) if safe_location
      if !request.inertia? && request.format.html? && safe_location
        return redirect_to(safe_location, status: :see_other)
      end
    end
    head :conflict
  end

  def validated_original_document_path
    value = request.original_fullpath.to_s
    return frontend_boundary_fallback_path unless valid_relative_original_path?(value)

    value
  end

  def valid_relative_original_path?(value)
    return false if value.blank? || !value.start_with?("/") || value.start_with?("//")
    return false if value.include?("\\") || value.include?("#")
    return false if value.match?(/[\x00-\x1f\x7f]/)

    uri = URI.parse(value)
    decoded_segments = uri.path.split("/").map { |segment| URI.decode_www_form_component(segment) }
    canonical_segments = decoded_segments.none? do |segment|
      segment.in?([".", ".."]) || segment.match?(/[\\\/\x00-\x1f\x7f]/)
    end
    uri.scheme.nil? && uri.host.nil? && uri.path.start_with?("/") && canonical_segments
  rescue URI::InvalidURIError, ArgumentError
    false
  end

  def frontend_boundary_fallback_path
    @frontend_application&.landing_path || "/"
  end

  def frontend_boundary_safe_get_path
    declared = @frontend_route_match&.safe_get_path
    return declared if declared && safe_frontend_get_path?(declared)

    fallback = @frontend_application&.landing_path
    safe_frontend_get_path?(fallback) ? fallback : "/"
  end

  def safe_frontend_get_path?(path)
    return false unless path

    match = frontend_application_registry.resolve(path:, method: "GET")
    match && %w[document inertia_page].include?(match.kind)
  end

  def merge_frontend_boundary_vary!
    current = response.get_header("Vary").to_s
      .split(",")
      .map(&:strip)
      .reject(&:blank?)
    VARY_HEADERS.each do |header|
      current << header unless current.any? { |existing| existing.casecmp?(header) }
    end
    response.set_header("Vary", current.join(", "))
  end

  def validate_inertia_component_boundary!(component)
    unless @frontend_route_match&.application
      raise Frontend::ApplicationRegistry::ComponentBoundaryViolation,
        "Inertia component #{component.inspect} is rendered from an unowned route"
    end

    kind = @frontend_route_match.kind
    transitional_website_document = kind == "document" &&
      @frontend_application.id == "website" &&
      @frontend_application.runtime_kind == "inertia_document"
    unless kind.in?(%w[inertia_page application_action]) || transitional_website_document
      raise Frontend::ApplicationRegistry::ComponentBoundaryViolation,
        "Inertia component #{component.inspect} cannot render from #{kind.inspect} route"
    end

    frontend_application_registry.assert_component!(
      application_id: @frontend_route_match.application_id,
      component:,
      product_owner: @frontend_route_match.product_owner
    )
  end

  def inertia_component_from_render_arguments(args, options)
    render_options = if options.key?(:inertia)
      options
    elsif args.first.is_a?(Hash) && args.first.key?(:inertia)
      args.first
    end
    return unless render_options

    component = render_options[:inertia]
    return unless component
    return component if component.is_a?(String) || component.is_a?(Symbol)

    inertia_configuration.component_path_resolver(
      path: controller_path,
      action: action_name
    )
  end

  def frontend_application_registry
    Frontend::ApplicationRegistry.instance
  end

  def frontend_application_id
    @frontend_application&.id
  end

  def frontend_application_entrypoint
    return @frontend_application.entrypoint if @frontend_application

    raise Frontend::ApplicationRegistry::UnknownApplication,
      "no frontend application owns #{request.request_method} #{request.path}"
  end

  def frontend_application_runtime_kind
    @frontend_application&.runtime_kind
  end
end
