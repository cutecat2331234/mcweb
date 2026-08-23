export interface SecureEvidenceAttachment {
  public_id: string
  filename: string
  byte_size: number
  state: string
  scan_status: string | null
  scan_status_url: string
  download_url: string
  discard_url?: string
  retention_until?: string
  updated_at?: string
  idempotent?: boolean
}

export interface SecureEvidenceUploadCopy {
  add: string
  processing: string
  limit: string
  uploadFailed: string
  scanFailed: string
  scanTimeout: string
}
