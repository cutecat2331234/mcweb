# frozen_string_literal: true

module FeatureGuard
  extend ActiveSupport::Concern

  included do
    before_action :ensure_feature_enabled_for_request, unless: :skip_feature_guard?
  end

  class_methods do
    def skip_feature_guard(**options)
      skip_before_action :ensure_feature_enabled_for_request, **options
    end
  end

  private

  def ensure_feature_enabled_for_request
    return if admin_request?
    return if setup_request?
    return if health_request?

    feature_id = FeatureFlags.feature_for_path(request.path)
    return if feature_id.nil?
    return if FeatureFlags.enabled?(feature_id)

    redirect_to redirect_path_for_disabled_feature(feature_id), alert: FeatureFlags.disabled_message(feature_id)
  end

  def redirect_path_for_disabled_feature(feature_id)
    case feature_id
    when :website_blog
      root_path
    else
      FeatureFlags.primary_portal_path(self)
    end
  end

  def admin_request?
    request.path.start_with?("/admin")
  end

  def health_request?
    request.path.start_with?("/health")
  end

  def skip_feature_guard?
    false
  end
end
