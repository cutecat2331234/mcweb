# frozen_string_literal: true

require Rails.root.join("lib/mcweb/identity_data_export_registrar_config")

Mcweb::IdentityDataExportRegistrarConfig.initialize!(Rails.application.config.x)

Rails.application.reloader.to_prepare do
  Identity::DataExportCatalog.finalize!
end
