<script setup lang="ts">
import { ref, computed } from 'vue'
import { Link, router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { Message } from '@mcweb/ui'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { confirm } from '@/lib/arcoConfirm'
import { isAdminSpaNavigationHref } from '@/lib/adminNavigation'
import { createIdempotencyKey } from '@/lib/idempotency'
import { HttpError, postJson } from '@/lib/http'

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
  data?: Record<string, unknown>
  external?: boolean
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
  muteForm?: MuteForm | null
  banForm?: BanForm | null
  refundForm?: RefundForm | null
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
  expire_days: '' as number | string,
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

async function runAction(action: DetailAction) {
  if (action.confirm) {
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
    router.visit(action.href)
    return
  }
  router.visit(action.href, { method, data: action.data })
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
  <div class="admin-generic-show">
    <a-page-header
      :title="title"
      :subtitle="subtitle"
      :show-back="false"
      class="mb-4 !px-0"
    />

    <a-card class="max-w-3xl" :bordered="true">
      <a-descriptions :column="{ xs: 1, sm: 1 }" bordered>
        <a-descriptions-item
          v-for="field in displayFields"
          :key="field.key || field.label"
          :label="field.label"
        >
          <span class="break-words font-medium">{{ field.value }}</span>
        </a-descriptions-item>
      </a-descriptions>
    </a-card>

    <a-card
      v-if="props.accountForm && canEditAccountAccess"
      class="mt-6 max-w-3xl"
      :title="t('admin.genericShow.accountAccess')"
      :bordered="true"
    >
      <a-alert
        class="mb-5"
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

    <a-card
      v-for="section in sections"
      :key="section.title"
      class="mt-6 max-w-3xl"
      :title="section.title"
      :bordered="true"
    >
      <a-list :bordered="false" size="small">
        <a-list-item v-for="(item, index) in section.items" :key="index">
          <div class="break-words">
            <code v-if="item.label" class="text-xs text-[var(--color-text-3)]">
              {{ item.label }}
            </code>
            <span v-if="item.value"> — {{ item.value }}</span>
          </div>
        </a-list-item>
      </a-list>
    </a-card>

    <a-card
      v-if="preformatted"
      class="mt-6 max-w-3xl"
      :title="preformatted.title"
      :bordered="true"
    >
      <pre class="admin-generic-show__pre">{{ preformatted.content }}</pre>
    </a-card>

    <a-card
      v-for="section in preformattedSections"
      :key="section.title"
      class="mt-6 max-w-3xl"
      :title="section.title"
      :bordered="true"
    >
      <pre class="admin-generic-show__pre">{{ section.content }}</pre>
    </a-card>

    <a-card
      v-if="props.muteForm"
      class="mt-6 max-w-lg"
      :title="t('admin.genericShow.muteUser')"
      :bordered="true"
    >
      <form class="grid gap-4" @submit.prevent="submitMute">
        <label class="admin-generic-show__field">
          <span>{{ t('admin.common.reason') }}</span>
          <a-input v-model="muteForm.reason" :placeholder="t('admin.genericShow.muteReason')" />
        </label>
        <label class="admin-generic-show__field">
          <span>{{ t('admin.genericShow.expiresAt') }}</span>
          <a-input v-model="muteForm.expires_at" type="datetime-local" />
        </label>
        <div>
          <a-button
            html-type="submit"
            type="primary"
            status="danger"
            size="small"
            :loading="muteForm.processing"
          >
            {{ t('admin.genericShow.mute') }}
          </a-button>
        </div>
      </form>
    </a-card>

    <a-card
      v-if="props.banForm && !props.banForm.banned"
      class="mt-6 max-w-lg"
      :title="t('admin.genericShow.banUser')"
      :bordered="true"
    >
      <form class="grid gap-4" @submit.prevent="submitBan">
        <label class="admin-generic-show__field">
          <span>{{ t('admin.genericShow.banReason') }}</span>
          <a-input v-model="banForm.reason" :placeholder="t('admin.genericShow.banReason')" />
        </label>
        <label class="admin-generic-show__field">
          <span>{{ t('admin.genericShow.expiresAt') }}</span>
          <a-input v-model="banForm.expires_at" type="datetime-local" />
        </label>
        <div>
          <a-button
            html-type="submit"
            type="primary"
            status="danger"
            size="small"
            :loading="banForm.processing"
          >
            {{ t('admin.genericShow.banAccount') }}
          </a-button>
        </div>
      </form>
    </a-card>

    <a-card v-if="props.banForm?.banned" class="mt-6 max-w-lg" :bordered="true">
      <a-alert type="error" show-icon class="mb-4">
        {{ t('admin.genericShow.bannedNotice') }}
      </a-alert>
      <a-button type="outline" size="small" @click="submitUnban">
        {{ t('admin.genericShow.unban') }}
      </a-button>
    </a-card>

    <a-card
      v-if="props.refundForm"
      class="mt-6 max-w-lg"
      :title="t('admin.genericShow.partialRefund')"
      :bordered="true"
    >
      <form class="grid gap-4" @submit.prevent="submitRefund">
        <p class="text-xs text-[var(--color-text-3)]">
          {{ t('admin.genericShow.maxRefund', { amount: props.refundForm.max_label }) }}
        </p>
        <label class="admin-generic-show__field">
          <span>{{ t('admin.genericShow.refundCents') }}</span>
          <a-input-number
            v-model="refundForm.amount_cents"
            :max="props.refundForm.max_cents"
            :min="1"
            required
          />
        </label>
        <label class="admin-generic-show__field">
          <span>{{ t('admin.common.reason') }}</span>
          <a-input v-model="refundForm.reason" :placeholder="t('admin.genericShow.refundReason')" />
        </label>
        <div>
          <a-button
            html-type="submit"
            type="primary"
            size="small"
            :loading="refundForm.processing"
          >
            {{ t('admin.genericShow.processRefund') }}
          </a-button>
        </div>
      </form>
    </a-card>

    <a-card
      v-if="props.badgeForm"
      class="mt-6 max-w-lg"
      :title="t('admin.genericShow.grantBadge')"
      :bordered="true"
    >
      <form class="grid gap-4" @submit.prevent="submitBadge">
        <p v-if="props.badgeForm.earned.length" class="text-xs text-[var(--color-text-3)]">
          {{ t('admin.genericShow.earnedBadges', { badges: props.badgeForm.earned.join(t('common.listSeparator')) }) }}
        </p>
        <label class="admin-generic-show__field">
          <span>{{ t('admin.genericShow.selectBadge') }}</span>
          <a-select v-model="badgeSlug" :options="badgeOptions" allow-clear />
        </label>
        <a-space wrap>
          <a-button html-type="submit" type="primary" size="small">
            {{ t('admin.genericShow.grant') }}
          </a-button>
          <a-button
            v-if="props.badgeForm.revoke_url"
            type="outline"
            size="small"
            @click="revokeBadge"
          >
            {{ t('admin.genericShow.revoke') }}
          </a-button>
        </a-space>
      </form>
    </a-card>

    <a-card
      v-if="props.warningForm"
      class="mt-6 max-w-lg"
      :title="t('admin.genericShow.warning')"
      :bordered="true"
    >
      <form class="grid gap-4" @submit.prevent="submitWarning">
        <p class="text-xs text-[var(--color-text-3)]">
          {{ t('admin.genericShow.warningPoints', { points: props.warningForm.warning_points }) }}
        </p>
        <label class="admin-generic-show__field">
          <span>{{ t('admin.genericShow.warningReason') }}</span>
          <a-input
            v-model="warningForm.reason"
            :placeholder="t('admin.genericShow.warningReasonPlaceholder')"
            required
          />
        </label>
        <label class="admin-generic-show__field">
          <span>{{ t('admin.genericShow.warningPointsLabel') }}</span>
          <a-input-number v-model="warningForm.points" :min="1" :max="10" />
        </label>
        <label class="admin-generic-show__field">
          <span>{{ t('admin.genericShow.warningExpireDays') }}</span>
          <a-input
            v-model="warningForm.expire_days"
            type="number"
            min="0"
            :placeholder="t('admin.genericShow.warningExpireDaysPlaceholder')"
          />
        </label>
        <div>
          <a-button
            html-type="submit"
            type="primary"
            status="danger"
            size="small"
            :loading="warningForm.processing"
          >
            {{ t('admin.genericShow.issueWarning') }}
          </a-button>
        </div>
      </form>
    </a-card>

    <a-card
      v-if="props.shippingForm"
      class="mt-6 max-w-lg"
      :title="t('admin.genericShow.shippingManagement')"
      :bordered="true"
    >
      <form class="grid gap-4" @submit.prevent="submitShipping">
        <a-alert v-if="props.shippingForm.shipped" type="info" show-icon>
          {{ t('admin.genericShow.orderAlreadyShipped') }}
        </a-alert>
        <label class="admin-generic-show__field">
          <span>{{ t('admin.genericShow.trackingNumber') }}</span>
          <a-input
            v-model="shippingForm.tracking_number"
            :placeholder="t('admin.genericShow.trackingNumberPlaceholder')"
          />
        </label>
        <label class="admin-generic-show__field">
          <span>{{ t('admin.genericShow.shippingCarrier') }}</span>
          <a-input
            v-model="shippingForm.shipping_carrier"
            :placeholder="t('admin.genericShow.shippingCarrierPlaceholder')"
          />
        </label>
        <a-checkbox v-if="!props.shippingForm.shipped" v-model="shippingForm.mark_shipped">
          {{ t('admin.genericShow.markShipped') }}
        </a-checkbox>
        <div>
          <a-button
            html-type="submit"
            type="primary"
            size="small"
            :loading="shippingForm.processing"
          >
            {{ t('admin.genericShow.saveShipping') }}
          </a-button>
        </div>
      </form>
    </a-card>

    <a-card
      v-if="props.staffNoteForm"
      class="mt-6 max-w-lg"
      :title="t('admin.genericShow.staffNote')"
      :bordered="true"
    >
      <form class="grid gap-4" @submit.prevent="submitStaffNote">
        <p class="text-xs text-[var(--color-text-3)]">{{ t('admin.genericShow.staffNoteHint') }}</p>
        <label class="admin-generic-show__field">
          <span>{{ t('admin.genericShow.noteBody') }}</span>
          <a-textarea
            v-model="staffNoteForm.body"
            :placeholder="t('admin.genericShow.notePlaceholder')"
            :auto-size="{ minRows: 2, maxRows: 6 }"
            required
          />
        </label>
        <a-checkbox v-model="staffNoteForm.visible_to_customer">
          {{ t('admin.genericShow.visibleToBuyer') }}
        </a-checkbox>
        <div>
          <a-button
            html-type="submit"
            type="primary"
            size="small"
            :loading="staffNoteForm.processing"
          >
            {{ t('admin.genericShow.saveNote') }}
          </a-button>
        </div>
      </form>
    </a-card>

    <a-card v-if="props.spamCleanForm" class="mt-6 max-w-lg" :bordered="true">
      <a-alert
        type="warning"
        show-icon
        :title="t('admin.genericShow.spamCleanTitle')"
        class="mb-4"
      >
        {{ t('admin.genericShow.spamCleanHint') }}
      </a-alert>
      <a-button type="primary" status="danger" size="small" @click="cleanSpam">
        {{ t('admin.genericShow.spamCleanAction') }}
      </a-button>
    </a-card>

    <a-card
      v-if="props.storeCreditForm"
      class="mt-6 max-w-lg"
      :title="t('admin.genericShow.storeCredit')"
      :bordered="true"
    >
      <a-space direction="vertical" fill :size="16">
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
        <div>
          <a-button type="primary" status="warning" @click="openStoreCreditModal">
            {{ t('admin.genericShow.openStoreCreditAdjustment') }}
          </a-button>
        </div>
      </a-space>
    </a-card>

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
      <a-steps :current="storeCreditStep" size="small" class="mb-5">
        <a-step :title="t('admin.genericShow.storeCreditStepDetails')" />
        <a-step :title="t('admin.genericShow.storeCreditStepReview')" />
      </a-steps>

      <a-alert
        v-if="storeCreditError"
        class="mb-4"
        type="error"
        show-icon
        :closable="false"
      >
        {{ storeCreditError }}
      </a-alert>

      <a-alert
        class="mb-5"
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

          <div class="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
            <a-button
              class="w-full sm:w-auto"
              :disabled="storeCreditAuthorizing"
              @click="closeStoreCreditModal"
            >
              {{ t('common.cancel') }}
            </a-button>
            <a-button
              class="w-full sm:w-auto"
              type="primary"
              status="warning"
              :loading="storeCreditAuthorizing"
              :disabled="!canAuthorizeStoreCredit"
              @click="authorizeStoreCredit"
            >
              {{ t('admin.genericShow.storeCreditAuthorize') }}
            </a-button>
          </div>
        </template>

        <template v-else>
          <a-descriptions :column="1" bordered size="small" class="mb-4">
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
              <code class="break-all text-xs">{{ storeCreditAuthorization.request_id }}</code>
            </a-descriptions-item>
          </a-descriptions>

          <a-alert type="info" show-icon class="mb-4">
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
              <div class="mt-1 grid gap-2">
                <span>{{ t('admin.genericShow.storeCreditConfirmationHint') }}</span>
                <a-tag color="orangered" class="w-fit max-w-full">
                  <code class="break-all">{{ storeCreditAuthorization.confirmation }}</code>
                </a-tag>
              </div>
            </template>
          </a-form-item>

          <div class="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
            <a-button
              class="w-full sm:w-auto"
              :disabled="storeCreditSubmitting"
              @click="editStoreCreditRequest"
            >
              {{ t('admin.genericShow.storeCreditBackToEdit') }}
            </a-button>
            <a-button
              class="w-full sm:w-auto"
              type="primary"
              status="danger"
              :loading="storeCreditSubmitting"
              :disabled="!canSubmitStoreCredit"
              @click="submitStoreCredit"
            >
              {{ t('admin.genericShow.confirmStoreCreditAdjustment') }}
            </a-button>
          </div>
        </template>
      </a-form>
    </a-modal>

    <a-card
      v-if="props.silenceForm"
      class="mt-6 max-w-lg"
      :title="t('admin.genericShow.silence')"
      :bordered="true"
    >
      <p class="mb-4 text-xs text-[var(--color-text-3)]">
        {{ t('admin.genericShow.silenceHint') }}
      </p>
      <a-alert v-if="props.silenceForm.silenced" type="warning" show-icon class="mb-4">
        {{ t('admin.genericShow.silencedNotice') }}
      </a-alert>
      <form v-if="!props.silenceForm.silenced" class="grid gap-4" @submit.prevent="submitSilence">
        <label class="admin-generic-show__field">
          <span>{{ t('admin.common.reason') }}</span>
          <a-input v-model="silenceForm.reason" :placeholder="t('admin.common.optional')" />
        </label>
        <label class="admin-generic-show__field">
          <span>{{ t('admin.genericShow.days') }}</span>
          <a-input-number
            v-model="silenceForm.days"
            :min="1"
            :placeholder="t('admin.genericShow.daysPlaceholder')"
          />
        </label>
        <div>
          <a-button
            html-type="submit"
            type="primary"
            status="danger"
            size="small"
            :loading="silenceForm.processing"
          >
            {{ t('admin.genericShow.applySilence') }}
          </a-button>
        </div>
      </form>
      <a-button v-else type="outline" size="small" @click="submitUnsilence">
        {{ t('admin.genericShow.removeSilence') }}
      </a-button>
    </a-card>

    <a-card
      v-if="props.trustLevelForm"
      class="mt-6 max-w-lg"
      :title="t('admin.genericShow.trustLevel')"
      :bordered="true"
    >
      <form class="grid gap-4" @submit.prevent="submitTrustLevel">
        <p class="text-xs text-[var(--color-text-3)]">
          {{ t('admin.genericShow.currentTrust', { level: props.trustLevelForm.current_level }) }}
        </p>
        <label class="admin-generic-show__field">
          <span>{{ t('admin.genericShow.manualOverride') }}</span>
          <a-select v-model="trustLevelOverride" :options="trustLevelOptions" />
        </label>
        <div>
          <a-button html-type="submit" type="primary" size="small">
            {{ t('admin.genericShow.saveTrust') }}
          </a-button>
        </div>
      </form>
    </a-card>

    <a-space class="mt-6" wrap :size="[12, 12]">
      <template v-for="action in actions" :key="action.href + action.label">
        <a-button
          v-if="action.method && action.method !== 'get'"
          :type="action.variant === 'outline' ? 'outline' : 'primary'"
          :status="action.method === 'delete' ? 'danger' : undefined"
          @click="runAction(action)"
        >
          {{ action.label }}
        </a-button>
        <a-button
          v-else-if="action.confirm"
          :type="action.variant === 'default' ? 'primary' : 'outline'"
          @click="runAction(action)"
        >
          {{ action.label }}
        </a-button>
        <Link
          v-else-if="!action.external && isAdminSpaNavigationHref(action.href)"
          :href="action.href"
          class="arco-btn arco-btn-size-medium no-underline"
          :class="action.variant === 'default' ? 'arco-btn-primary' : 'arco-btn-outline'"
        >
          {{ action.label }}
        </Link>
        <a
          v-else
          :href="action.href"
          target="_blank"
          rel="noopener"
          data-admin-hard-navigation
          class="arco-btn arco-btn-size-medium no-underline"
          :class="action.variant === 'default' ? 'arco-btn-primary' : 'arco-btn-outline'"
        >
          {{ action.label }}
        </a>
      </template>
      <Link
        :href="backUrl"
        class="arco-btn arco-btn-outline arco-btn-size-medium no-underline"
      >
        {{ t('admin.genericShow.back') }}
      </Link>
    </a-space>
  </div>
</template>

<style scoped>
.admin-generic-show__field {
  display: grid;
  gap: 6px;
  font-size: 14px;
  color: var(--color-text-2);
}

.admin-generic-show__pre {
  max-width: 100%;
  overflow: auto;
  border-radius: 4px;
  background: var(--color-fill-2);
  padding: 16px;
  font-size: 12px;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}

.admin-generic-show :deep(.arco-list-content) {
  overflow: hidden;
}
</style>
