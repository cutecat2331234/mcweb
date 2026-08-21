<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { router, useForm } from '@inertiajs/vue3'
import type { RequestPayload } from '@inertiajs/core'
import { useI18n } from 'vue-i18n'
import { Message } from '@mcweb/ui'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { confirm } from '@/lib/arcoConfirm'
import { isAdminSpaNavigationHref } from '@/lib/adminNavigation'
import { createIdempotencyKey } from '@/lib/idempotency'
import { HttpError, postJson } from '@/lib/http'
import HighRiskActionModal from '@/components/admin/HighRiskActionModal.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

export interface DetailField {
  key?: string
  label: string
  value: string
}

export interface DetailSection {
  title: string
  items: Array<{ label: string; value?: string }>
}

export interface DetailAction {
  label: string
  href: string
  method?: 'get' | 'post' | 'patch' | 'delete'
  confirm?: string
  variant?: 'default' | 'outline'
  data?: RequestPayload
  external?: boolean
}

export interface OperationNotice {
  type: 'info' | 'warning' | 'error' | 'success'
  title: string
  description?: string
}

export interface HighRiskAction {
  key: string
  label: string
  title: string
  authorization_url: string
  action_url: string
  method?: 'post' | 'patch' | 'put' | 'delete'
  data?: Record<string, unknown>
}

export interface MuteForm {
  user_id: string
  action_url: string
}

export interface RefundForm {
  action_url: string
  max_cents: number
  max_label: string
}

export interface BanForm {
  banned: boolean
  ban_url: string
  unban_url: string
}

export interface BadgeForm {
  action_url: string
  revoke_url?: string
  badges: Array<{ slug: string; name: string }>
  earned: string[]
}

export interface WarningForm {
  action_url: string
  warning_points: number
}

export interface StaffNoteForm {
  action_url: string
}

export interface ShippingForm {
  action_url: string
  tracking_number: string
  shipping_carrier: string
  shipped: boolean
}

export interface SilenceForm {
  silenced: boolean
  silence_url: string
  unsilence_url: string
}

export interface TrustLevelForm {
  action_url: string
  current_level: number
  override: number | null
  levels: Array<{ value: number; label: string }>
}

export interface StoreCreditForm {
  action_url: string
  authorization_url: string
  balance_cents: number
  balance_label: string
}

interface StoreCreditAuthorization {
  token: string
  confirmation: string
  request_id: string
  expires_in: number
  amount_cents: number
  amount_label: string
  balance_before_cents: number
  balance_before_label: string
  balance_after_cents: number
  balance_after_label: string
}

export interface AccountForm {
  action_url: string
  account_type?: string
  account_types?: Array<{ value: string; label: string }>
  admin_modules?: string[]
  module_options?: string[]
  role_ids?: number[]
  roles?: Array<{ id: number; name: string; key: string }>
}

const props = defineProps<{
  title: string
  subtitle?: string
  fields: DetailField[]
  sections?: DetailSection[]
  preformatted?: { title: string; content: string }
  preformattedSections?: Array<{ title: string; content: string }>
  actions?: DetailAction[]
  highRiskActions?: HighRiskAction[]
  muteForm?: MuteForm | null
  banForm?: BanForm | null
  refundForm?: RefundForm | null
  operationNotice?: OperationNotice | null
  badgeForm?: BadgeForm | null
  warningForm?: WarningForm | null
  staffNoteForm?: StaffNoteForm | null
  spamCleanForm?: { action_url: string } | null
  shippingForm?: ShippingForm | null
  silenceForm?: SilenceForm | null
  trustLevelForm?: TrustLevelForm | null
  storeCreditForm?: StoreCreditForm | null
  accountForm?: AccountForm | null
  backUrl: string
}>()

const trustLevelOverride = ref(props.trustLevelForm?.override?.toString() ?? 'auto')

const badgeSlug = ref('')
type OperationPanel =
  | 'mute'
  | 'ban'
  | 'refund'
  | 'badge'
  | 'warning'
  | 'shipping'
  | 'staffNote'
  | 'spam'
  | 'storeCredit'
  | 'silence'
  | 'trust'

const detailTab = ref<'overview' | 'sections' | 'raw' | 'operations'>('overview')
const operationDrawer = ref<OperationPanel | null>(null)
const isMobile = ref(false)
let viewportQuery: MediaQueryList | null = null

function syncViewport(event?: MediaQueryListEvent) {
  isMobile.value = event?.matches ?? viewportQuery?.matches ?? false
}

onMounted(() => {
  viewportQuery = window.matchMedia('(max-width: 767px)')
  syncViewport()
  viewportQuery.addEventListener('change', syncViewport)
})

onBeforeUnmount(() => {
  viewportQuery?.removeEventListener('change', syncViewport)
})

const operationEntries = computed(() => [
  ...(props.muteForm ? [{ key: 'mute' as const, label: t('admin.genericShow.muteUser'), danger: true }] : []),
  ...(props.banForm ? [{
    key: 'ban' as const,
    label: props.banForm.banned ? t('admin.genericShow.unban') : t('admin.genericShow.banUser'),
    danger: true,
  }] : []),
  ...(props.refundForm ? [{ key: 'refund' as const, label: t('admin.genericShow.partialRefund'), danger: false }] : []),
  ...(props.badgeForm ? [{ key: 'badge' as const, label: t('admin.genericShow.grantBadge'), danger: false }] : []),
  ...(props.warningForm ? [{ key: 'warning' as const, label: t('admin.genericShow.warning'), danger: true }] : []),
  ...(props.shippingForm ? [{ key: 'shipping' as const, label: t('admin.genericShow.shippingManagement'), danger: false }] : []),
  ...(props.staffNoteForm ? [{ key: 'staffNote' as const, label: t('admin.genericShow.staffNote'), danger: false }] : []),
  ...(props.spamCleanForm ? [{ key: 'spam' as const, label: t('admin.genericShow.spamCleanTitle'), danger: true }] : []),
  ...(props.storeCreditForm ? [{ key: 'storeCredit' as const, label: t('admin.genericShow.storeCredit'), danger: false }] : []),
  ...(props.silenceForm ? [{
    key: 'silence' as const,
    label: props.silenceForm.silenced ? t('admin.genericShow.removeSilence') : t('admin.genericShow.silence'),
    danger: true,
  }] : []),
  ...(props.trustLevelForm ? [{ key: 'trust' as const, label: t('admin.genericShow.trustLevel'), danger: false }] : []),
])

const operationTitle = computed(() =>
  operationEntries.value.find((entry) => entry.key === operationDrawer.value)?.label || '',
)

const hasStructuredSections = computed(() => Boolean(props.sections?.length))
const hasRawContent = computed(() => Boolean(props.preformatted || props.preformattedSections?.length))

const badgeOptions = computed(() => [
  { value: '', label: t('admin.common.pleaseSelect') },
  ...(props.badgeForm?.badges || []).map((badge) => ({ value: badge.slug, label: badge.name })),
])

const trustLevelOptions = computed(() => [
  { value: 'auto', label: t('admin.genericShow.autoTrust') },
  ...(props.trustLevelForm?.levels || []).map((level) => ({ value: String(level.value), label: level.label })),
])

function accountTypeLabel(value: string, fallback: string) {
  switch (value) {
    case 'member':
      return t('admin.genericShow.accountTypeMember')
    case 'staff':
      return t('admin.genericShow.accountTypeStaff')
    case 'admin':
      return t('admin.genericShow.accountTypeAdmin')
    case 'owner':
      return t('admin.genericShow.accountTypeOwner')
    default:
      return fallback || value
  }
}

function adminModuleLabel(moduleKey: string) {
  switch (moduleKey) {
    case 'forum':
      return t('admin.genericShow.adminModuleForum')
    case 'store':
      return t('admin.genericShow.adminModuleStore')
    case 'minecraft':
      return t('admin.genericShow.adminModuleMinecraft')
    case 'system':
      return t('admin.genericShow.adminModuleSystem')
    case 'website':
      return t('admin.genericShow.adminModuleWebsite')
    case 'identity':
      return t('admin.genericShow.adminModuleIdentity')
    default:
      return moduleKey
  }
}

const accountTypeOptions = computed(() =>
  (props.accountForm?.account_types || []).map((option) => ({
    value: option.value,
    label: accountTypeLabel(option.value, option.label),
  })),
)

const adminModuleOptions = computed(() =>
  (props.accountForm?.module_options || []).map((moduleKey) => ({
    value: moduleKey,
    label: adminModuleLabel(moduleKey),
  })),
)

const accountRoleOptions = computed(() =>
  (props.accountForm?.roles || []).map((role) => ({
    value: role.id,
    label: role.name,
  })),
)

const canEditAccountAccess = computed(() =>
  accountTypeOptions.value.length > 0
  || adminModuleOptions.value.length > 0
  || accountRoleOptions.value.length > 0,
)

const accountAccessForm = useForm({
  user: {
    account_type: props.accountForm?.account_type || 'member',
    admin_modules: [ ...(props.accountForm?.admin_modules || []) ],
    role_ids: [ ...(props.accountForm?.role_ids || []) ],
  },
})

const warningForm = useForm({
  reason: '',
  points: 1,
  expire_days: 0,
})

const staffNoteForm = useForm({
  body: '',
  visible_to_customer: false,
})

const storeCreditForm = useForm({
  amount_cents: 0,
  note: '',
  confirmation: '',
  request_id: '',
})
const storeCreditModalVisible = ref(false)
const storeCreditAuthorization = ref<StoreCreditAuthorization | null>(null)
const storeCreditAuthorizing = ref(false)
const storeCreditSubmitting = ref(false)
const storeCreditError = ref('')
const storeCreditBalanceLabel = ref(props.storeCreditForm?.balance_label || '')
const highRiskModalVisible = ref(false)
const selectedHighRiskAction = ref<HighRiskAction | null>(null)
const displayFields = computed(() =>
  props.fields.map((field) => (
    field.key === 'store_credit'
      ? { ...field, value: storeCreditBalanceLabel.value }
      : field
  )),
)
const storeCreditStep = computed(() => storeCreditAuthorization.value ? 2 : 1)
const canAuthorizeStoreCredit = computed(() =>
  Number.isInteger(Number(storeCreditForm.amount_cents))
  && Number(storeCreditForm.amount_cents) !== 0
  && storeCreditForm.note.trim().length > 0
  && !storeCreditAuthorizing.value
  && !storeCreditSubmitting.value,
)
const canSubmitStoreCredit = computed(() =>
  Boolean(storeCreditAuthorization.value)
  && storeCreditForm.confirmation === storeCreditAuthorization.value?.confirmation
  && !storeCreditAuthorizing.value
  && !storeCreditSubmitting.value,
)

const silenceForm = useForm({
  reason: '',
  days: 7,
})

const muteForm = useForm({
  user_id: props.muteForm?.user_id || '',
  reason: '',
  expires_at: '',
})

const banForm = useForm({
  reason: '',
  expires_at: '',
})

const refundForm = useForm({
  amount_cents: props.refundForm?.max_cents || 0,
  reason: '',
})

const shippingForm = useForm({
  tracking_number: props.shippingForm?.tracking_number || '',
  shipping_carrier: props.shippingForm?.shipping_carrier || '',
  mark_shipped: false,
})

async function runAction(action: DetailAction, confirmed = false) {
  if (action.confirm && !confirmed) {
    const ok = await confirm({
      title: t('admin.common.confirmOperation'),
      message: action.confirm,
      confirmLabel: t('admin.common.continue'),
      variant: action.method === 'delete' ? 'destructive' : 'default',
    })
    if (!ok) return
  }
  const method = action.method || 'get'
  if (method === 'get') {
    if (action.external || !isAdminSpaNavigationHref(action.href)) {
      window.open(action.href, '_blank', 'noopener')
      return
    }
    router.visit(action.href)
    return
  }
  router.visit(action.href, { method, data: action.data })
}

function openHighRiskAction(action: HighRiskAction) {
  selectedHighRiskAction.value = action
  highRiskModalVisible.value = true
}

function highRiskCompleted(result: Record<string, unknown>) {
  const redirectUrl = result.redirect_url
  if (typeof redirectUrl === 'string' && redirectUrl.length > 0) {
    router.visit(redirectUrl)
    return
  }
  router.reload({ preserveScroll: true })
}

function highRiskMethod(action: HighRiskAction | null) {
  return (action?.method || 'post').toUpperCase() as 'POST' | 'PATCH' | 'PUT' | 'DELETE'
}

function submitMute() {
  if (!props.muteForm) return
  muteForm.post(props.muteForm.action_url)
}

function submitBan() {
  if (!props.banForm || props.banForm.banned) return
  banForm.post(props.banForm.ban_url)
}

function submitUnban() {
  if (!props.banForm || !props.banForm.banned) return
  router.post(props.banForm.unban_url)
}

function submitRefund() {
  if (!props.refundForm) return
  router.patch(props.refundForm.action_url, {
    refund: true,
    amount_cents: refundForm.amount_cents,
    reason: refundForm.reason,
  })
}

function submitShipping() {
  if (!props.shippingForm) return
  router.patch(props.shippingForm.action_url, {
    shipping: true,
    tracking_number: shippingForm.tracking_number,
    shipping_carrier: shippingForm.shipping_carrier,
    mark_shipped: shippingForm.mark_shipped,
  }, { preserveScroll: true })
}

function submitBadge() {
  if (!props.badgeForm || !badgeSlug.value) return
  router.post(props.badgeForm.action_url, { badge_slug: badgeSlug.value })
}

function revokeBadge() {
  if (!props.badgeForm?.revoke_url || !badgeSlug.value) return
  router.post(props.badgeForm.revoke_url, { badge_slug: badgeSlug.value })
}

function submitWarning() {
  if (!props.warningForm) return
  warningForm.post(props.warningForm.action_url, {
    preserveScroll: true,
    onSuccess: () => { warningForm.reset() },
  })
}

function submitStaffNote() {
  if (!props.staffNoteForm) return
  staffNoteForm.post(props.staffNoteForm.action_url, {
    preserveScroll: true,
    onSuccess: () => { staffNoteForm.reset('body'); staffNoteForm.visible_to_customer = false },
  })
}

async function cleanSpam() {
  if (!props.spamCleanForm) return
  const ok = await confirm({
    title: t('admin.genericShow.spamCleanTitle'),
    message: t('admin.genericShow.spamCleanConfirm'),
    confirmLabel: t('admin.genericShow.spamCleanAction'),
    variant: 'destructive',
  })
  if (!ok) return
  router.post(props.spamCleanForm.action_url, {}, { preserveScroll: true })
}

function openStoreCreditModal() {
  resetStoreCreditFlow()
  storeCreditModalVisible.value = true
}

function closeStoreCreditModal() {
  if (storeCreditAuthorizing.value || storeCreditSubmitting.value) return
  storeCreditModalVisible.value = false
  resetStoreCreditFlow()
}

function resetStoreCreditFlow() {
  storeCreditForm.reset()
  storeCreditForm.request_id = createIdempotencyKey()
  storeCreditForm.clearErrors()
  storeCreditAuthorization.value = null
  storeCreditError.value = ''
}

function storeCreditErrorMessage(error: unknown) {
  if (error instanceof HttpError && error.body && typeof error.body === 'object') {
    const message = (error.body as { error?: unknown }).error
    if (typeof message === 'string' && message.length > 0) return message
  }
  return t('admin.genericShow.storeCreditRequestFailed')
}

async function authorizeStoreCredit() {
  if (!props.storeCreditForm || !canAuthorizeStoreCredit.value) return

  storeCreditAuthorizing.value = true
  storeCreditError.value = ''
  try {
    const authorization = await postJson<StoreCreditAuthorization>(
      props.storeCreditForm.authorization_url,
      {
        amount_cents: storeCreditForm.amount_cents,
        note: storeCreditForm.note,
        request_id: storeCreditForm.request_id,
      },
    )
    storeCreditAuthorization.value = authorization
    storeCreditForm.request_id = authorization.request_id
    storeCreditForm.confirmation = ''
  } catch (error) {
    storeCreditError.value = storeCreditErrorMessage(error)
  } finally {
    storeCreditAuthorizing.value = false
  }
}

function editStoreCreditRequest() {
  if (storeCreditSubmitting.value) return
  storeCreditAuthorization.value = null
  storeCreditForm.confirmation = ''
  storeCreditForm.request_id = createIdempotencyKey()
  storeCreditError.value = ''
}

async function submitStoreCredit() {
  const authorization = storeCreditAuthorization.value
  if (!props.storeCreditForm || !authorization || !canSubmitStoreCredit.value) return

  storeCreditSubmitting.value = true
  storeCreditError.value = ''
  try {
    const result = await postJson<{
      balance_cents: number
      balance_label: string
      request_id: string
      idempotent: boolean
    }>(
      props.storeCreditForm.action_url,
      {
        amount_cents: storeCreditForm.amount_cents,
        note: storeCreditForm.note,
        request_id: storeCreditForm.request_id,
        authorization_token: authorization.token,
        confirmation: storeCreditForm.confirmation,
      },
    )
    storeCreditBalanceLabel.value = result.balance_label
    storeCreditModalVisible.value = false
    resetStoreCreditFlow()
    Message.success(t('admin.genericShow.storeCreditUpdated'))
  } catch (error) {
    storeCreditError.value = storeCreditErrorMessage(error)
  } finally {
    storeCreditSubmitting.value = false
  }
}

function submitSilence() {
  if (!props.silenceForm) return
  silenceForm.post(props.silenceForm.silence_url, {
    preserveScroll: true,
    onSuccess: () => { silenceForm.reset() },
  })
}

function submitUnsilence() {
  if (!props.silenceForm) return
  router.post(props.silenceForm.unsilence_url, {}, { preserveScroll: true })
}

function submitTrustLevel() {
  if (!props.trustLevelForm) return
  router.post(props.trustLevelForm.action_url, {
    forum_trust_level_override: trustLevelOverride.value,
  }, { preserveScroll: true })
}

function submitAccountAccess() {
  if (!props.accountForm) return
  accountAccessForm.patch(props.accountForm.action_url, { preserveScroll: true })
}
</script>

<template>
  <a-space direction="vertical" :size="16" fill>
    <a-page-header
      :title="title"
      :subtitle="subtitle"
      :show-back="false"
    >
      <template #extra>
        <a-button @click="router.visit(backUrl)">
          {{ t('admin.genericShow.back') }}
        </a-button>
      </template>
    </a-page-header>

    <a-alert
      v-if="props.operationNotice"
      :type="props.operationNotice.type"
      :title="props.operationNotice.title"
      :description="props.operationNotice.description"
      show-icon
    />

    <a-card :bordered="true">
      <a-tabs v-model:active-key="detailTab" type="line">
        <a-tab-pane key="overview" :title="t('admin.overview')">
          <a-space direction="vertical" size="large" fill>
            <a-descriptions :column="{ xs: 1, md: 2, xl: 3 }" bordered>
              <a-descriptions-item
                v-for="field in displayFields"
                :key="field.key || field.label"
                :label="field.label"
              >
                <a-typography-text :ellipsis="{ rows: 2, showTooltip: true }">
                  {{ field.value }}
                </a-typography-text>
              </a-descriptions-item>
            </a-descriptions>

            <a-card v-if="actions?.length" :title="t('admin.ui.actions')" :bordered="true">
              <a-space wrap>
                <template v-for="action in actions" :key="action.href + action.label">
                  <a-popconfirm
                    v-if="action.confirm"
                    :content="action.confirm"
                    :ok-text="t('admin.common.continue')"
                    :cancel-text="t('common.cancel')"
                    @ok="runAction(action, true)"
                  >
                    <a-button
                      :type="action.variant === 'outline' ? 'outline' : 'primary'"
                      :status="action.method === 'delete' ? 'danger' : undefined"
                    >
                      {{ action.label }}
                    </a-button>
                  </a-popconfirm>
                  <a-button
                    v-else
                    :type="action.variant === 'outline' ? 'outline' : 'primary'"
                    :status="action.method === 'delete' ? 'danger' : undefined"
                    @click="runAction(action)"
                  >
                    {{ action.label }}
                  </a-button>
                </template>
              </a-space>
            </a-card>
          </a-space>
        </a-tab-pane>

        <a-tab-pane v-if="hasStructuredSections" key="sections" :title="t('admin.common.description')">
          <a-collapse accordion>
            <a-collapse-item
              v-for="(section, sectionIndex) in sections"
              :key="section.title"
              :header="section.title"
              :name="String(sectionIndex)"
            >
              <a-list :bordered="false" size="small">
                <a-list-item v-for="(item, index) in section.items" :key="index">
                  <a-space wrap>
                    <a-typography-text v-if="item.label" code>{{ item.label }}</a-typography-text>
                    <a-typography-text v-if="item.value">{{ item.value }}</a-typography-text>
                  </a-space>
                </a-list-item>
              </a-list>
            </a-collapse-item>
          </a-collapse>
        </a-tab-pane>

        <a-tab-pane v-if="hasRawContent" key="raw" :title="t('admin.common.body')">
          <a-collapse>
            <a-collapse-item v-if="preformatted" :header="preformatted.title" name="primary">
              <a-textarea
                :model-value="preformatted.content"
                readonly
                :auto-size="{ minRows: 8, maxRows: 24 }"
              />
            </a-collapse-item>
            <a-collapse-item
              v-for="(section, index) in preformattedSections"
              :key="section.title"
              :header="section.title"
              :name="`raw-${index}`"
            >
              <a-textarea
                :model-value="section.content"
                readonly
                :auto-size="{ minRows: 8, maxRows: 24 }"
              />
            </a-collapse-item>
          </a-collapse>
        </a-tab-pane>

        <a-tab-pane key="operations" :title="t('admin.ui.actions')">
          <a-grid
            v-if="operationEntries.length || highRiskActions?.length"
            :cols="{ xs: 1, md: 2, xl: 3 }"
            :col-gap="16"
            :row-gap="16"
          >
            <a-grid-item v-for="entry in operationEntries" :key="entry.key">
              <a-card :title="entry.label" size="small" :bordered="true">
                <a-button
                  :type="entry.danger ? 'outline' : 'primary'"
                  :status="entry.danger ? 'danger' : undefined"
                  @click="operationDrawer = entry.key"
                >
                  {{ entry.label }}
                </a-button>
              </a-card>
            </a-grid-item>
            <a-grid-item v-for="action in highRiskActions || []" :key="action.key">
              <a-card :title="action.label" size="small" :bordered="true">
                <a-button type="primary" status="warning" @click="openHighRiskAction(action)">
                  {{ action.label }}
                </a-button>
              </a-card>
            </a-grid-item>
          </a-grid>
          <a-result v-else status="info" :title="t('admin.ui.noResults')" />
        </a-tab-pane>
      </a-tabs>
    </a-card>

    <a-card
      v-if="props.accountForm && canEditAccountAccess"
      :title="t('admin.genericShow.accountAccess')"
      :bordered="true"
    >
      <a-alert
        type="info"
        show-icon
        :title="t('admin.genericShow.accountAccessHint')"
      />

      <a-form :model="accountAccessForm.user" layout="vertical" @submit="submitAccountAccess">
        <a-grid :cols="{ xs: 1, md: 2 }" :col-gap="20" :row-gap="4">
          <a-grid-item>
            <a-form-item field="account_type" :label="t('admin.genericShow.accountType')">
              <a-select
                v-model="accountAccessForm.user.account_type"
                :options="accountTypeOptions"
              />
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item field="role_ids" :label="t('admin.genericShow.roles')">
              <a-select
                v-model="accountAccessForm.user.role_ids"
                :options="accountRoleOptions"
                :placeholder="t('admin.genericShow.rolesPlaceholder')"
                multiple
                allow-clear
                allow-search
              />
            </a-form-item>
          </a-grid-item>
        </a-grid>

        <a-form-item
          field="admin_modules"
          :label="t('admin.genericShow.adminModules')"
          :extra="accountAccessForm.user.account_type === 'staff'
            ? t('admin.genericShow.adminModulesHint')
            : t('admin.genericShow.adminModulesStaffOnly')"
        >
          <a-checkbox-group
            v-model="accountAccessForm.user.admin_modules"
            :disabled="accountAccessForm.user.account_type !== 'staff'"
          >
            <a-grid :cols="{ xs: 1, sm: 2, lg: 3 }" :col-gap="12" :row-gap="12">
              <a-grid-item
                v-for="option in adminModuleOptions"
                :key="option.value"
              >
                <a-checkbox :value="option.value">
                  {{ option.label }}
                </a-checkbox>
              </a-grid-item>
            </a-grid>
          </a-checkbox-group>
        </a-form-item>

        <a-button
          html-type="submit"
          type="primary"
          :loading="accountAccessForm.processing"
        >
          {{ t('admin.genericShow.saveAccountAccess') }}
        </a-button>
      </a-form>
    </a-card>

    <a-drawer
      :visible="operationDrawer !== null"
      :title="operationTitle"
      :width="isMobile ? '100%' : 520"
      :footer="false"
      unmount-on-close
      @cancel="operationDrawer = null"
    >
      <a-form v-if="operationDrawer === 'mute' && props.muteForm" :model="muteForm" layout="vertical" @submit="submitMute">
        <a-form-item field="reason" :label="t('admin.common.reason')">
          <a-input v-model="muteForm.reason" :placeholder="t('admin.genericShow.muteReason')" />
        </a-form-item>
        <a-form-item field="expires_at" :label="t('admin.genericShow.expiresAt')">
          <a-date-picker
            v-model="muteForm.expires_at"
            show-time
            value-format="YYYY-MM-DDTHH:mm"
            allow-clear
          />
        </a-form-item>
        <a-button
          html-type="submit"
          type="primary"
          status="danger"
          :loading="muteForm.processing"
        >
          {{ t('admin.genericShow.mute') }}
        </a-button>
      </a-form>

      <template v-else-if="operationDrawer === 'ban' && props.banForm">
        <a-result
          v-if="props.banForm.banned"
          status="warning"
          :title="t('admin.genericShow.bannedNotice')"
        >
          <template #extra>
            <a-popconfirm
              :content="t('admin.common.confirmOperation')"
              :ok-text="t('admin.common.continue')"
              :cancel-text="t('common.cancel')"
              @ok="submitUnban"
            >
          <a-button type="primary">{{ t('admin.genericShow.unban') }}</a-button>
            </a-popconfirm>
          </template>
        </a-result>
        <a-form v-else :model="banForm" layout="vertical" @submit="submitBan">
          <a-form-item field="reason" :label="t('admin.genericShow.banReason')">
            <a-input v-model="banForm.reason" :placeholder="t('admin.genericShow.banReason')" />
          </a-form-item>
          <a-form-item field="expires_at" :label="t('admin.genericShow.expiresAt')">
            <a-date-picker
              v-model="banForm.expires_at"
              show-time
              value-format="YYYY-MM-DDTHH:mm"
              allow-clear
            />
          </a-form-item>
          <a-button
            html-type="submit"
            type="primary"
            status="danger"
            :loading="banForm.processing"
          >
            {{ t('admin.genericShow.banAccount') }}
          </a-button>
        </a-form>
      </template>

      <a-form
        v-else-if="operationDrawer === 'refund' && props.refundForm"
        :model="refundForm"
        layout="vertical"
        @submit="submitRefund"
      >
        <a-alert type="info">
          {{ t('admin.genericShow.maxRefund', { amount: props.refundForm.max_label }) }}
        </a-alert>
        <a-form-item field="amount_cents" :label="t('admin.genericShow.refundCents')">
          <a-input-number
            v-model="refundForm.amount_cents"
            :max="props.refundForm.max_cents"
            :min="1"
            required
          />
        </a-form-item>
        <a-form-item field="reason" :label="t('admin.common.reason')">
          <a-input v-model="refundForm.reason" :placeholder="t('admin.genericShow.refundReason')" />
        </a-form-item>
        <a-button html-type="submit" type="primary" :loading="refundForm.processing">
          {{ t('admin.genericShow.processRefund') }}
        </a-button>
      </a-form>

      <a-form
        v-else-if="operationDrawer === 'badge' && props.badgeForm"
        :model="{ badgeSlug }"
        layout="vertical"
        @submit="submitBadge"
      >
        <a-alert v-if="props.badgeForm.earned.length" type="info">
          {{ t('admin.genericShow.earnedBadges', { badges: props.badgeForm.earned.join(t('common.listSeparator')) }) }}
        </a-alert>
        <a-form-item field="badgeSlug" :label="t('admin.genericShow.selectBadge')">
          <a-select v-model="badgeSlug" :options="badgeOptions" allow-clear />
        </a-form-item>
        <a-space wrap>
        <a-button html-type="submit" type="primary" :disabled="!badgeSlug">
            {{ t('admin.genericShow.grant') }}
          </a-button>
          <a-button
            v-if="props.badgeForm.revoke_url"
            type="outline"
            :disabled="!badgeSlug"
            @click="revokeBadge"
          >
            {{ t('admin.genericShow.revoke') }}
          </a-button>
        </a-space>
      </a-form>

      <a-form
        v-else-if="operationDrawer === 'warning' && props.warningForm"
        :model="warningForm"
        layout="vertical"
        @submit="submitWarning"
      >
        <a-alert type="warning">
          {{ t('admin.genericShow.warningPoints', { points: props.warningForm.warning_points }) }}
        </a-alert>
        <a-form-item field="reason" :label="t('admin.genericShow.warningReason')">
          <a-input
            v-model="warningForm.reason"
            :placeholder="t('admin.genericShow.warningReasonPlaceholder')"
            required
          />
        </a-form-item>
        <a-form-item field="points" :label="t('admin.genericShow.warningPointsLabel')">
          <a-input-number v-model="warningForm.points" :min="1" :max="10" />
        </a-form-item>
        <a-form-item field="expire_days" :label="t('admin.genericShow.warningExpireDays')">
          <a-input-number
            v-model="warningForm.expire_days"
            :min="0"
            :placeholder="t('admin.genericShow.warningExpireDaysPlaceholder')"
          />
        </a-form-item>
        <a-button
          html-type="submit"
          type="primary"
          status="danger"
          :loading="warningForm.processing"
        >
          {{ t('admin.genericShow.issueWarning') }}
        </a-button>
      </a-form>

      <a-form
        v-else-if="operationDrawer === 'shipping' && props.shippingForm"
        :model="shippingForm"
        layout="vertical"
        @submit="submitShipping"
      >
        <a-alert v-if="props.shippingForm.shipped" type="info" show-icon>
          {{ t('admin.genericShow.orderAlreadyShipped') }}
        </a-alert>
        <a-form-item field="tracking_number" :label="t('admin.genericShow.trackingNumber')">
          <a-input
            v-model="shippingForm.tracking_number"
            :placeholder="t('admin.genericShow.trackingNumberPlaceholder')"
          />
        </a-form-item>
        <a-form-item field="shipping_carrier" :label="t('admin.genericShow.shippingCarrier')">
          <a-input
            v-model="shippingForm.shipping_carrier"
            :placeholder="t('admin.genericShow.shippingCarrierPlaceholder')"
          />
        </a-form-item>
        <a-form-item v-if="!props.shippingForm.shipped" field="mark_shipped">
          <a-checkbox v-model="shippingForm.mark_shipped">{{ t('admin.genericShow.markShipped') }}</a-checkbox>
        </a-form-item>
        <a-button html-type="submit" type="primary" :loading="shippingForm.processing">
          {{ t('admin.genericShow.saveShipping') }}
        </a-button>
      </a-form>

      <a-form
        v-else-if="operationDrawer === 'staffNote' && props.staffNoteForm"
        :model="staffNoteForm"
        layout="vertical"
        @submit="submitStaffNote"
      >
        <a-alert type="info">{{ t('admin.genericShow.staffNoteHint') }}</a-alert>
        <a-form-item field="body" :label="t('admin.genericShow.noteBody')">
          <a-textarea
            v-model="staffNoteForm.body"
            :placeholder="t('admin.genericShow.notePlaceholder')"
            :auto-size="{ minRows: 4, maxRows: 10 }"
            required
          />
        </a-form-item>
        <a-form-item field="visible_to_customer">
          <a-checkbox v-model="staffNoteForm.visible_to_customer">
            {{ t('admin.genericShow.visibleToBuyer') }}
          </a-checkbox>
        </a-form-item>
        <a-button html-type="submit" type="primary" :loading="staffNoteForm.processing">
          {{ t('admin.genericShow.saveNote') }}
        </a-button>
      </a-form>

      <a-space v-else-if="operationDrawer === 'spam' && props.spamCleanForm" direction="vertical" size="large" fill>
        <a-alert type="warning" show-icon :title="t('admin.genericShow.spamCleanTitle')">
          {{ t('admin.genericShow.spamCleanHint') }}
        </a-alert>
        <a-button type="primary" status="danger" @click="cleanSpam">
          {{ t('admin.genericShow.spamCleanAction') }}
        </a-button>
      </a-space>

      <a-space
        v-else-if="operationDrawer === 'storeCredit' && props.storeCreditForm"
        direction="vertical"
        :size="16"
        fill
      >
        <a-alert
          type="warning"
          show-icon
          :title="t('admin.genericShow.storeCreditRiskTitle')"
        >
          {{ t('admin.genericShow.storeCreditRiskHint') }}
        </a-alert>
        <a-descriptions :column="1" size="small" bordered>
          <a-descriptions-item :label="t('admin.genericShow.balanceLabel')">
            <strong>{{ storeCreditBalanceLabel }}</strong>
          </a-descriptions-item>
        </a-descriptions>
        <a-button type="primary" status="warning" @click="openStoreCreditModal">
          {{ t('admin.genericShow.openStoreCreditAdjustment') }}
        </a-button>
      </a-space>

      <template v-else-if="operationDrawer === 'silence' && props.silenceForm">
        <a-result
          v-if="props.silenceForm.silenced"
          status="warning"
          :title="t('admin.genericShow.silencedNotice')"
          :subtitle="t('admin.genericShow.silenceHint')"
        >
          <template #extra>
            <a-popconfirm
              :content="t('admin.common.confirmOperation')"
              :ok-text="t('admin.common.continue')"
              :cancel-text="t('common.cancel')"
              @ok="submitUnsilence"
            >
              <a-button type="primary">{{ t('admin.genericShow.removeSilence') }}</a-button>
            </a-popconfirm>
          </template>
        </a-result>
        <a-form v-else :model="silenceForm" layout="vertical" @submit="submitSilence">
          <a-alert type="info">{{ t('admin.genericShow.silenceHint') }}</a-alert>
          <a-form-item field="reason" :label="t('admin.common.reason')">
            <a-input v-model="silenceForm.reason" :placeholder="t('admin.common.optional')" />
          </a-form-item>
          <a-form-item field="days" :label="t('admin.genericShow.days')">
            <a-input-number
              v-model="silenceForm.days"
              :min="1"
              :placeholder="t('admin.genericShow.daysPlaceholder')"
            />
          </a-form-item>
          <a-button
            html-type="submit"
            type="primary"
            status="danger"
            :loading="silenceForm.processing"
          >
            {{ t('admin.genericShow.applySilence') }}
          </a-button>
        </a-form>
      </template>

      <a-form
        v-else-if="operationDrawer === 'trust' && props.trustLevelForm"
        :model="{ trustLevelOverride }"
        layout="vertical"
        @submit="submitTrustLevel"
      >
        <a-alert type="info">
          {{ t('admin.genericShow.currentTrust', { level: props.trustLevelForm.current_level }) }}
        </a-alert>
        <a-form-item field="trustLevelOverride" :label="t('admin.genericShow.manualOverride')">
          <a-select v-model="trustLevelOverride" :options="trustLevelOptions" />
        </a-form-item>
        <a-button html-type="submit" type="primary">
          {{ t('admin.genericShow.saveTrust') }}
        </a-button>
      </a-form>
    </a-drawer>

    <a-modal
      v-if="props.storeCreditForm"
      v-model:visible="storeCreditModalVisible"
      :title="t('admin.genericShow.storeCreditModalTitle')"
      :footer="false"
      :mask-closable="!storeCreditAuthorizing && !storeCreditSubmitting"
      :esc-to-close="!storeCreditAuthorizing && !storeCreditSubmitting"
      :width="'min(560px, calc(100vw - 32px))'"
      @cancel="closeStoreCreditModal"
    >
      <a-steps :current="storeCreditStep" size="small">
        <a-step :title="t('admin.genericShow.storeCreditStepDetails')" />
        <a-step :title="t('admin.genericShow.storeCreditStepReview')" />
      </a-steps>

      <a-space direction="vertical" :size="16" fill>
        <a-alert
          v-if="storeCreditError"
          type="error"
          show-icon
          :closable="false"
        >
          {{ storeCreditError }}
        </a-alert>

        <a-alert
          type="warning"
          show-icon
          :closable="false"
          :title="t('admin.genericShow.storeCreditAuditTitle')"
        >
          {{ t('admin.genericShow.storeCreditAuditHint') }}
        </a-alert>

        <a-form :model="storeCreditForm" layout="vertical">
          <template v-if="!storeCreditAuthorization">
            <a-form-item
              field="amount_cents"
              :label="t('admin.genericShow.adjustCents')"
              required
            >
              <a-input-number
                v-model="storeCreditForm.amount_cents"
                :disabled="storeCreditAuthorizing"
              />
            </a-form-item>

            <a-form-item
              field="note"
              :label="t('admin.genericShow.note')"
              :extra="t('admin.genericShow.storeCreditNoteRequired')"
              required
            >
              <a-textarea
                v-model="storeCreditForm.note"
                :placeholder="t('admin.genericShow.storeCreditNotePlaceholder')"
                :auto-size="{ minRows: 3, maxRows: 6 }"
                :max-length="1000"
                show-word-limit
                :disabled="storeCreditAuthorizing"
              />
            </a-form-item>

            <a-space justify="end" wrap>
              <a-button
                :disabled="storeCreditAuthorizing"
                @click="closeStoreCreditModal"
              >
                {{ t('common.cancel') }}
              </a-button>
              <a-button
                type="primary"
                status="warning"
                :loading="storeCreditAuthorizing"
                :disabled="!canAuthorizeStoreCredit"
                @click="authorizeStoreCredit"
              >
                {{ t('admin.genericShow.storeCreditAuthorize') }}
              </a-button>
            </a-space>
          </template>

          <template v-else>
            <a-descriptions :column="1" bordered size="small">
              <a-descriptions-item :label="t('admin.genericShow.storeCreditBefore')">
                {{ storeCreditAuthorization.balance_before_label }}
              </a-descriptions-item>
              <a-descriptions-item :label="t('admin.genericShow.storeCreditChange')">
                <a-tag :color="storeCreditAuthorization.amount_cents > 0 ? 'green' : 'red'">
                  {{ storeCreditAuthorization.amount_label }}
                </a-tag>
              </a-descriptions-item>
              <a-descriptions-item :label="t('admin.genericShow.storeCreditAfter')">
                <strong>{{ storeCreditAuthorization.balance_after_label }}</strong>
              </a-descriptions-item>
              <a-descriptions-item :label="t('admin.genericShow.storeCreditRequestId')">
                <code>{{ storeCreditAuthorization.request_id }}</code>
              </a-descriptions-item>
            </a-descriptions>

            <a-alert type="info" show-icon>
              {{
                t('admin.genericShow.storeCreditAuthorizationExpiry', {
                  minutes: Math.max(1, Math.ceil(storeCreditAuthorization.expires_in / 60)),
                })
              }}
            </a-alert>

            <a-form-item
              field="confirmation"
              :label="t('admin.genericShow.storeCreditConfirmation')"
              required
            >
              <a-input
                v-model="storeCreditForm.confirmation"
                :placeholder="t('admin.genericShow.storeCreditConfirmationPlaceholder')"
                :disabled="storeCreditSubmitting"
                autocomplete="off"
              />
              <template #extra>
                <a-space direction="vertical" :size="8" fill>
                  <span>{{ t('admin.genericShow.storeCreditConfirmationHint') }}</span>
                  <a-tag color="orangered">
                    <code>{{ storeCreditAuthorization.confirmation }}</code>
                  </a-tag>
                </a-space>
              </template>
            </a-form-item>

            <a-space justify="end" wrap>
              <a-button
                :disabled="storeCreditSubmitting"
                @click="editStoreCreditRequest"
              >
                {{ t('admin.genericShow.storeCreditBackToEdit') }}
              </a-button>
              <a-button
                type="primary"
                status="danger"
                :loading="storeCreditSubmitting"
                :disabled="!canSubmitStoreCredit"
                @click="submitStoreCredit"
              >
                {{ t('admin.genericShow.confirmStoreCreditAdjustment') }}
              </a-button>
            </a-space>
          </template>
        </a-form>
      </a-space>
    </a-modal>

    <HighRiskActionModal
      v-if="selectedHighRiskAction"
      v-model:visible="highRiskModalVisible"
      :title="selectedHighRiskAction.title"
      :authorization-url="selectedHighRiskAction.authorization_url"
      :action-url="selectedHighRiskAction.action_url"
      :method="highRiskMethod(selectedHighRiskAction)"
      :payload="selectedHighRiskAction.data || {}"
      @completed="highRiskCompleted"
    />
  </a-space>
</template>
