export interface SecureEvidenceAttachment {
  public_id: string
  filename: string
  byte_size: number
  sha256: string
  state: string
  scan_status: string | null
  scan_status_url: string
  download_url: string
  discard_url?: string
  sealed?: boolean
  audience?: 'appellant' | 'reviewers'
}

export type ReportAppealStatus =
  | 'draft'
  | 'submitted'
  | 'under_review'
  | 'upheld'
  | 'overturned'
  | 'cancelled'

export interface ReportAppealReviewRow {
  public_id: string
  appellant_role: 'reporter' | 'affected_subject'
  appellant: string
  status: ReportAppealStatus
  submitted_at: string | null
  state_changed_at: string
  report_target: string
  detail_url: string
}

export interface ReportAppealReviewDetail extends ReportAppealReviewRow {
  lock_version: number
  decision_url: string
  evidence_url: string | null
  evidence_upload_url: string
  evidence_subject: { key: 'community.report_appeal'; public_id: string }
  can_add_evidence: boolean
  can_decide: boolean
  public_case: {
    reason: string
    public_outcome_code: 'upheld' | 'overturned' | 'cancelled' | null
    events: Array<{ type: string; occurred_at: string }>
  }
  internal_case: {
    report_public_id: string
    report_status: string
    report_reason_label: string
    report_reason_detail: string | null
    reporter: string
    affected_user: string | null
    reviewer: string | null
    internal_note: string | null
  }
  attachments: SecureEvidenceAttachment[]
}

export interface ReportAppealPagination {
  page: number
  pages: number
  count: number
}
