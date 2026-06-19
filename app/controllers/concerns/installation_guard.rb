# frozen_string_literal: true

module InstallationGuard
  extend ActiveSupport::Concern

  included do
    before_action :redirect_to_setup_unless_locked, unless: :skip_installation_guard?
    before_action :block_setup_when_locked, if: :setup_controller?
  end

  class_methods do
    def skip_installation_guard(**options)
      skip_before_action :redirect_to_setup_unless_locked, **options
      skip_before_action :block_setup_when_locked, **options
    end
  end

  private

  def redirect_to_setup_unless_locked
    return if InstallationLock.locked?
    return if setup_request?

    redirect_to setup_root_path
  end

  def block_setup_when_locked
    return unless InstallationLock.locked?

    redirect_to root_path, alert: t("mcweb.flash.installation_locked")
  end

  def setup_controller?
    is_a?(Setup::WizardController)
  end

  def setup_request?
    request.path.start_with?("/setup")
  end

  def skip_installation_guard?
    false
  end
end
