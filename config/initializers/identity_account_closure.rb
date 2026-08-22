# frozen_string_literal: true

require Rails.root.join("lib/mcweb/identity_account_closure_registrar_config")

Mcweb::IdentityAccountClosureRegistrarConfig.initialize!(Rails.application.config.x)

Rails.application.reloader.to_prepare do
  Identity::AccountClosureCatalog.finalize!
end
