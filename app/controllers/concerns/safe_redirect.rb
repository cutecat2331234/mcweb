# frozen_string_literal: true

module SafeRedirect
  extend ActiveSupport::Concern

  private

  def safe_local_redirect_path(url, fallback:)
    location = url.to_s.strip
    return fallback if location.blank?
    return fallback if location.start_with?("//")
    return fallback unless location.start_with?("/")
    return fallback if location.include?("\\")
    return fallback if location.match?(/[\x00-\x1f\x7f]/)

    location
  end

  def safe_referer_path(fallback:)
    referer = request.referer.to_s.strip
    return fallback if referer.blank?

    uri = URI.parse(referer)
    return fallback unless uri.host.present?
    return fallback unless uri.host.casecmp?(request.host)
    return fallback unless uri.scheme.in?(%w[http https])

    path = uri.path.presence || "/"
    path += "?#{uri.query}" if uri.query.present?
    path += "##{uri.fragment}" if uri.fragment.present?
    safe_local_redirect_path(path, fallback: fallback)
  rescue URI::InvalidURIError
    fallback
  end
end
