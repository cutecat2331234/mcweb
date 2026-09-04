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
  lock_version: number
  reason: string
  created_at?: string
  expires_at?: string
  phase?: string
  rolled_back?: boolean
  recovery_required?: boolean
  error_code?: string
  resumable: boolean
  is_expired: boolean
  authorize_url?: string
  execute_url?: string
  cancel_url?: string
  plan_recovery_url?: string
  recovery_resolution?: WorldRestoreResolutionRow
}

export interface WorldRestoreResolutionRow {
  id: string
  status: string
  resolution_action: 'resume' | 'rollback' | 'reconcile'
  reason: string
  lock_version: number
  created_at?: string
  expires_at?: string
  authorization_expires_at?: string
  expired_at?: string
  lifecycle_action?: 'cancel' | 'takeover'
  lifecycle_reason?: string
  lifecycle_actor_id?: string
  supersedes_resolution_id?: string
  error_code?: string
  recovery_resolution_proof?: boolean
  verified_world_state?: string
  resumable: boolean
  is_expired: boolean
  authorize_url?: string
  execute_url?: string
  cancel_url?: string
  takeover_url?: string
}

export interface WorldSafetyProps {
  visible: boolean
  can_create_backup: boolean
  can_restore: boolean
  can_resolve_recovery: boolean
  create_backup_url?: string
  create_restore_url?: string
  refresh_url: string
  start_blocked: boolean
  backup_blockers: string[]
  restore_blockers: string[]
  recovery_blockers: string[]
  backups: ManagedWorldBackup[]
  plans: WorldRestorePlanRow[]
}
