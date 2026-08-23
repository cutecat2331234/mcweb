export interface ManagedWorldBackup {
  id: string
  purpose: string
  status: string
  restorable: boolean
  target_compatible: boolean
  created_at?: string
  verified_at?: string
  archive_bytes?: number
  uncompressed_bytes?: number
  entry_count?: number
  manifest_digest_short?: string
  world_relative_path?: string
  error_code?: string
}

export interface WorldRestorePlanRow {
  id: string
  backup_id: string
  pre_restore_backup_id?: string
  status: string
  reason: string
  created_at?: string
  expires_at?: string
  phase?: string
  rolled_back?: boolean
  recovery_required?: boolean
  error_code?: string
  authorize_url?: string
  execute_url?: string
}

export interface WorldSafetyProps {
  visible: boolean
  can_create_backup: boolean
  can_restore: boolean
  create_backup_url?: string
  create_restore_url?: string
  refresh_url: string
  start_blocked: boolean
  backup_blockers: string[]
  restore_blockers: string[]
  backups: ManagedWorldBackup[]
  plans: WorldRestorePlanRow[]
}
