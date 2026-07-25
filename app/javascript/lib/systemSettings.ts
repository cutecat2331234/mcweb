export const SYSTEM_SETTING_GROUP_ORDER = [
  'general',
  'features',
  'frontend',
  'forum',
  'store',
  'minecraft',
  'integrations',
  'advanced',
] as const

export type SystemSettingGroup = typeof SYSTEM_SETTING_GROUP_ORDER[number]
export type SystemSettingInputType = 'text' | 'number' | 'boolean' | 'password' | 'textarea'

export const KNOWN_SYSTEM_SETTING_KEYS = [
  'site.name',
  'site.url',
  'general.site_name',
  'features.forum.enabled',
  'features.minecraft.enabled',
  'features.store.enabled',
  'features.website_blog.enabled',
  'frontend.active_portal_template',
  'frontend.active_website_template',
  'forum.allow_op_close',
  'forum.auto_close_on_solved',
  'forum.bump_cooldown_hours',
  'forum.digest_hour',
  'forum.edit_grace_period_minutes',
  'forum.event_webhook_events',
  'forum.event_webhook_secret',
  'forum.event_webhook_url',
  'forum.extra_report_reasons',
  'forum.flag_abuse_threshold',
  'forum.group_pm_creator_only_add',
  'forum.group_pm_max_participants',
  'forum.max_daily_reactions',
  'forum.max_reactions_per_minute',
  'forum.max_reports_per_hour',
  'forum.max_upload_size_mb',
  'forum.min_trust_level_pm',
  'forum.min_trust_level_profile_post',
  'forum.min_trust_level_reaction',
  'forum.min_trust_level_signature',
  'forum.new_topic_window_days',
  'forum.online_peak_at',
  'forum.online_peak_count',
  'forum.points.daily_check_in',
  'forum.points.post_created',
  'forum.points.reaction_received',
  'forum.points.solution_accepted',
  'forum.profile_posts_enabled',
  'forum.reaction_emojis',
  'forum.reaction_scores',
  'forum.report_auto_hide_threshold',
  'forum.require_post_approval_below_tl',
  'forum.saved_search_digest_hour',
  'forum.saved_search_limit',
  'forum.saved_search_webhook_secret',
  'forum.saved_search_webhook_url',
  'forum.search_feeds_opml_history_limit',
  'forum.search_feeds_opml_saved_limit',
  'forum.signatures_enabled',
  'forum.signature_max_length',
  'forum.vapid_private_key',
  'forum.vapid_public_key',
  'forum.warning_block_links_threshold',
  'forum.warning_block_pm_threshold',
  'forum.warning_block_post_threshold',
  'forum.warning_mute_days',
  'forum.warning_mute_threshold',
  'forum.warning_points_expire_days',
  'forum.warning_suspend_days',
  'forum.warning_suspend_threshold',
  'minecraft.backup.enabled',
  'minecraft.backup.schedule',
  'minecraft.bridges.enabled',
  'minecraft.bridges.placeholders',
  'minecraft.commerce.pause_fulfill_during_maintenance',
  'minecraft.exec_command.allowed_prefixes',
  'minecraft.graceful_stop.commands',
  'minecraft.graceful_stop.countdown_seconds',
  'minecraft.graceful_stop.enabled',
  'minecraft.graceful_stop.message',
  'minecraft.link_command',
  'minecraft.profile.sections',
  'minecraft.profile.skin_mode',
  'store.abandoned_cart_coupon_code',
  'store.cart_max_items',
  'store.compare_max_items',
  'store.flat_shipping_cents',
  'store.free_shipping_min_order_cents',
  'store.gift_wrap_cents',
  'store.min_checkout_subtotal_cents',
  'store.order_webhook_secret',
  'store.order_webhook_url',
  'store.pending_order_expiry_minutes',
  'store.product_discussion_section_slug',
  'store.refund_window_days',
  'store.review_request_delay_days',
  'store.seo_description',
  'store.seo_title',
  'store.shipping_methods',
  'webhook.failure_alert_cooldown_hours',
  'webhook.failure_alert_email',
  'webhook.failure_alert_forum_threshold',
  'webhook.failure_alert_last_sent_at',
  'webhook.failure_alert_store_threshold',
  'webhook.failure_alert_threshold',
  'api.rate_limit_per_minute',
] as const

const READ_ONLY_KEYS = new Set<string>([
  'forum.online_peak_at',
  'forum.online_peak_count',
  'webhook.failure_alert_last_sent_at',
])

const MULTILINE_KEYS = new Set<string>([
  'forum.event_webhook_events',
  'forum.extra_report_reasons',
  'forum.reaction_emojis',
  'forum.reaction_scores',
  'minecraft.bridges.enabled',
  'minecraft.bridges.placeholders',
  'minecraft.exec_command.allowed_prefixes',
  'minecraft.graceful_stop.commands',
  'minecraft.profile.sections',
  'store.shipping_methods',
])

const BOOLEAN_KEYS = new Set<string>([
  'forum.allow_op_close',
  'forum.auto_close_on_solved',
  'forum.group_pm_creator_only_add',
  'forum.profile_posts_enabled',
  'forum.signatures_enabled',
  'minecraft.backup.enabled',
  'minecraft.commerce.pause_fulfill_during_maintenance',
  'minecraft.graceful_stop.enabled',
])

const NUMBER_KEYS = new Set<string>([
  'api.rate_limit_per_minute',
  'forum.bump_cooldown_hours',
  'forum.digest_hour',
  'forum.edit_grace_period_minutes',
  'forum.flag_abuse_threshold',
  'forum.group_pm_max_participants',
  'forum.max_daily_reactions',
  'forum.max_reactions_per_minute',
  'forum.max_reports_per_hour',
  'forum.max_upload_size_mb',
  'forum.min_trust_level_pm',
  'forum.min_trust_level_profile_post',
  'forum.min_trust_level_reaction',
  'forum.min_trust_level_signature',
  'forum.new_topic_window_days',
  'forum.online_peak_count',
  'forum.points.daily_check_in',
  'forum.points.post_created',
  'forum.points.reaction_received',
  'forum.points.solution_accepted',
  'forum.report_auto_hide_threshold',
  'forum.require_post_approval_below_tl',
  'forum.saved_search_digest_hour',
  'forum.saved_search_limit',
  'forum.search_feeds_opml_history_limit',
  'forum.search_feeds_opml_saved_limit',
  'forum.signature_max_length',
  'forum.warning_block_links_threshold',
  'forum.warning_block_pm_threshold',
  'forum.warning_block_post_threshold',
  'forum.warning_mute_days',
  'forum.warning_mute_threshold',
  'forum.warning_points_expire_days',
  'forum.warning_suspend_days',
  'forum.warning_suspend_threshold',
  'minecraft.graceful_stop.countdown_seconds',
  'store.cart_max_items',
  'store.compare_max_items',
  'store.flat_shipping_cents',
  'store.free_shipping_min_order_cents',
  'store.gift_wrap_cents',
  'store.min_checkout_subtotal_cents',
  'store.pending_order_expiry_minutes',
  'store.refund_window_days',
  'store.review_request_delay_days',
  'webhook.failure_alert_cooldown_hours',
  'webhook.failure_alert_forum_threshold',
  'webhook.failure_alert_store_threshold',
  'webhook.failure_alert_threshold',
])

export function systemSettingMessageId(key: string) {
  return key.replace(/[^a-zA-Z0-9]+/g, '_')
}

export function systemSettingGroup(key: string): SystemSettingGroup {
  if (key.startsWith('site.') || key.startsWith('general.')) return 'general'
  if (key.startsWith('features.')) return 'features'
  if (key.startsWith('frontend.')) return 'frontend'
  if (key.startsWith('forum.')) return 'forum'
  if (key.startsWith('store.')) return 'store'
  if (key.startsWith('minecraft.')) return 'minecraft'
  if (key.startsWith('webhook.')) return 'integrations'
  return 'advanced'
}

export function systemSettingInputType(key: string): SystemSettingInputType {
  if (key.startsWith('features.') && key.endsWith('.enabled')) return 'boolean'
  if (BOOLEAN_KEYS.has(key)) return 'boolean'
  if (/(?:secret|password|token|private_key)$/i.test(key)) return 'password'
  if (MULTILINE_KEYS.has(key)) return 'textarea'
  if (NUMBER_KEYS.has(key)) return 'number'
  return 'text'
}

export function systemSettingReadOnly(key: string) {
  return READ_ONLY_KEYS.has(key)
}

export function systemSettingBooleanValue(value: string) {
  return value === 'true' || value === '1'
}

export function systemSettingBooleanStorage(key: string, enabled: boolean) {
  if (key === 'forum.auto_close_on_solved') return enabled ? '1' : '0'
  return enabled ? 'true' : 'false'
}
