# frozen_string_literal: true

# Developer Mode deliberately disables the global browser policy so local
# proxies, source maps and HMR-like tooling can be inspected without editing
# the application policy. Endpoint-specific sandbox policies (downloads and
# uploads) are set by their controllers and remain in force.
unless Mcweb::DeveloperMode.allow?(:disable_csp)
  Rails.application.config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri :self
    policy.object_src :none
    policy.frame_ancestors :self
    policy.form_action :self
    policy.script_src :self, :https, :unsafe_inline
    policy.style_src :self, :https, :unsafe_inline
    policy.img_src :self, :https, :data, :blob
    policy.font_src :self, :https, :data
    policy.connect_src :self, :https, :wss
    policy.media_src :self, :https, :blob
    policy.worker_src :self, :blob
    policy.manifest_src :self
  end
end
