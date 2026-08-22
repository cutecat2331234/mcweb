# frozen_string_literal: true

require Rails.root.join("lib/mcweb/secure_evidence_subject_registrar_config")

Mcweb::SecureEvidenceSubjectRegistrarConfig.initialize!(Rails.application.config.x)

Rails.application.reloader.to_prepare do
  SecureEvidence::SubjectCatalog.finalize!
end
