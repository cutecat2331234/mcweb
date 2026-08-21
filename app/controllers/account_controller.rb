# frozen_string_literal: true

class AccountController < ApplicationController
  before_action :require_login

  def show
    render inertia: "Account/Show", props: {
      forum_enabled: FeatureFlags.enabled?(:forum),
      minecraft_enabled: FeatureFlags.enabled?(:minecraft)
    }
  end
end
