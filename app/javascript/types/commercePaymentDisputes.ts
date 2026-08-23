export interface CustomerPaymentDisputes {
  create: {
    allowed: boolean
    url: string
    max_amount_cents: number
    max_amount_label: string
    description_min_length: number
    description_max_length: number
    reason_options: Array<{ value: string; label: string }>
  }
  upload_url: string
  evidence_limits: { max_files: number; max_file_bytes: number }
  cases: Array<{
    public_id: string
    status: string
    status_label: string
    amount_label: string
    rights_status: string
    rights_status_label: string
    evidence_due_at?: string | null
    created_at: string
    updated_at: string
    can_upload_evidence: boolean
    can_withdraw: boolean
    withdraw_url?: string | null
    evidence_subject: { key: string; public_id: string }
    attachments: Array<{
      public_id: string
      filename: string
      byte_size: number
      byte_size_label: string
      state: string
      scan_status: string
      status_label: string
      created_at: string
      download_url?: string | null
      scan_status_url: string
    }>
    timeline: Array<{
      key: string
      label: string
      description?: string | null
      status?: string | null
      occurred_at: string
    }>
  }>
}
