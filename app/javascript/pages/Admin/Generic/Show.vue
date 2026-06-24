<script setup lang="ts">
import { ref, computed } from 'vue'
import { Link, router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Card from '@/components/ui/Card.vue'
import CardContent from '@/components/ui/CardContent.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Select from '@/components/ui/Select.vue'
import Checkbox from '@/components/ui/Checkbox.vue'
import { confirm } from '@/lib/useConfirm'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

export interface DetailField {
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
  balance_cents: number
  balance_label: string
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
  shippingForm?: ShippingForm | null
  silenceForm?: SilenceForm | null
  trustLevelForm?: TrustLevelForm | null
  storeCreditForm?: StoreCreditForm | null
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
})

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

function submitStoreCredit() {
  if (!props.storeCreditForm) return
  storeCreditForm.post(props.storeCreditForm.action_url, {
    preserveScroll: true,
    onSuccess: () => { storeCreditForm.reset() },
  })
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
</script>

<template>
  <PageHeader :title="title" :subtitle="subtitle" />

  <Card class="max-w-3xl">
    <CardContent class="space-y-3 pt-6">
      <div v-for="field in fields" :key="field.label" class="flex justify-between gap-4 text-sm">
        <span class="text-muted-foreground">{{ field.label }}</span>
        <span class="text-right font-medium">{{ field.value }}</span>
      </div>
    </CardContent>
  </Card>

  <div v-for="section in sections" :key="section.title" class="mt-6 max-w-3xl">
    <h2 class="mb-3 text-sm font-semibold">{{ section.title }}</h2>
    <ul class="space-y-2 rounded-lg border p-4 text-sm">
      <li v-for="(item, index) in section.items" :key="index">
        <code v-if="item.label" class="text-xs text-muted-foreground">{{ item.label }}</code>
        <span v-if="item.value"> — {{ item.value }}</span>
      </li>
    </ul>
  </div>

  <div v-if="preformatted" class="mt-6 max-w-3xl">
    <h2 class="mb-3 text-sm font-semibold">{{ preformatted.title }}</h2>
    <pre class="overflow-auto rounded-lg border bg-muted p-4 text-xs">{{ preformatted.content }}</pre>
  </div>

  <div v-for="section in preformattedSections" :key="section.title" class="mt-6 max-w-3xl">
    <h2 class="mb-3 text-sm font-semibold">{{ section.title }}</h2>
    <pre class="overflow-auto rounded-lg border bg-muted p-4 text-xs">{{ section.content }}</pre>
  </div>

  <form v-if="props.muteForm" class="mt-6 max-w-lg space-y-3 rounded-lg border p-4" @submit.prevent="submitMute">
    <h2 class="text-sm font-semibold">{{ t('admin.genericShow.muteUser') }}</h2>
    <div class="space-y-2">
      <Label>{{ t('admin.common.reason') }}</Label>
      <Input v-model="muteForm.reason" :placeholder="t('admin.genericShow.muteReason')" />
    </div>
    <div class="space-y-2">
      <Label>{{ t('admin.genericShow.expiresAt') }}</Label>
      <Input v-model="muteForm.expires_at" type="datetime-local" />
    </div>
    <Button type="submit" variant="destructive" size="sm" :disabled="muteForm.processing">{{ t('admin.genericShow.mute') }}</Button>
  </form>

  <form v-if="props.banForm && !props.banForm.banned" class="mt-6 max-w-lg space-y-3 rounded-lg border p-4" @submit.prevent="submitBan">
    <h2 class="text-sm font-semibold">{{ t('admin.genericShow.banUser') }}</h2>
    <div class="space-y-2">
      <Label>{{ t('admin.genericShow.banReason') }}</Label>
      <Input v-model="banForm.reason" :placeholder="t('admin.genericShow.banReason')" />
    </div>
    <div class="space-y-2">
      <Label>{{ t('admin.genericShow.expiresAt') }}</Label>
      <Input v-model="banForm.expires_at" type="datetime-local" />
    </div>
    <Button type="submit" variant="destructive" size="sm" :disabled="banForm.processing">{{ t('admin.genericShow.banAccount') }}</Button>
  </form>

  <div v-if="props.banForm?.banned" class="mt-6 max-w-lg rounded-lg border p-4">
    <p class="mb-3 text-sm text-destructive">{{ t('admin.genericShow.bannedNotice') }}</p>
    <Button type="button" size="sm" variant="outline" @click="submitUnban">{{ t('admin.genericShow.unban') }}</Button>
  </div>

  <form v-if="props.refundForm" class="mt-6 max-w-lg space-y-3 rounded-lg border p-4" @submit.prevent="submitRefund">
    <h2 class="text-sm font-semibold">{{ t('admin.genericShow.partialRefund') }}</h2>
    <p class="text-xs text-muted-foreground">{{ t('admin.genericShow.maxRefund', { amount: props.refundForm.max_label }) }}</p>
    <div class="space-y-2">
      <Label>{{ t('admin.genericShow.refundCents') }}</Label>
      <Input v-model.number="refundForm.amount_cents" type="number" :max="props.refundForm.max_cents" min="1" required />
    </div>
    <div class="space-y-2">
      <Label>{{ t('admin.common.reason') }}</Label>
      <Input v-model="refundForm.reason" :placeholder="t('admin.genericShow.refundReason')" />
    </div>
    <Button type="submit" size="sm" :disabled="refundForm.processing">{{ t('admin.genericShow.processRefund') }}</Button>
  </form>

  <form v-if="props.badgeForm" class="mt-6 max-w-lg space-y-3 rounded-lg border p-4" @submit.prevent="submitBadge">
    <h2 class="text-sm font-semibold">{{ t('admin.genericShow.grantBadge') }}</h2>
    <p v-if="props.badgeForm.earned.length" class="text-xs text-muted-foreground">{{ t('admin.genericShow.earnedBadges', { badges: props.badgeForm.earned.join(t('common.listSeparator')) }) }}</p>
    <div class="space-y-2">
      <Label>{{ t('admin.genericShow.selectBadge') }}</Label>
      <Select v-model="badgeSlug" :options="badgeOptions" block />
    </div>
    <div class="flex gap-2">
      <Button type="submit" size="sm">{{ t('admin.genericShow.grant') }}</Button>
      <Button v-if="props.badgeForm.revoke_url" type="button" size="sm" variant="outline" @click="revokeBadge">{{ t('admin.genericShow.revoke') }}</Button>
    </div>
  </form>

  <form v-if="props.warningForm" class="mt-6 max-w-lg space-y-3 rounded-lg border p-4" @submit.prevent="submitWarning">
    <h2 class="text-sm font-semibold">{{ t('admin.genericShow.warning') }}</h2>
    <p class="text-xs text-muted-foreground">{{ t('admin.genericShow.warningPoints', { points: props.warningForm.warning_points }) }}</p>
    <div class="space-y-2">
      <Label>{{ t('admin.genericShow.warningReason') }}</Label>
      <Input v-model="warningForm.reason" :placeholder="t('admin.genericShow.warningReasonPlaceholder')" required />
    </div>
    <div class="space-y-2">
      <Label>{{ t('admin.genericShow.warningPointsLabel') }}</Label>
      <Input v-model.number="warningForm.points" type="number" min="1" max="10" />
    </div>
    <div class="space-y-2">
      <Label>{{ t('admin.genericShow.warningExpireDays') }}</Label>
      <Input v-model.number="warningForm.expire_days" type="number" min="0" :placeholder="t('admin.genericShow.warningExpireDaysPlaceholder')" />
    </div>
    <Button type="submit" variant="destructive" size="sm" :disabled="warningForm.processing">{{ t('admin.genericShow.issueWarning') }}</Button>
  </form>

  <form v-if="props.shippingForm" class="mt-6 max-w-lg space-y-3 rounded-lg border p-4" @submit.prevent="submitShipping">
    <h2 class="text-sm font-semibold">{{ t('admin.genericShow.shippingManagement') }}</h2>
    <p v-if="props.shippingForm.shipped" class="text-xs text-muted-foreground">{{ t('admin.genericShow.orderAlreadyShipped') }}</p>
    <div class="space-y-2">
      <Label>{{ t('admin.genericShow.trackingNumber') }}</Label>
      <Input v-model="shippingForm.tracking_number" :placeholder="t('admin.genericShow.trackingNumberPlaceholder')" />
    </div>
    <div class="space-y-2">
      <Label>{{ t('admin.genericShow.shippingCarrier') }}</Label>
      <Input v-model="shippingForm.shipping_carrier" :placeholder="t('admin.genericShow.shippingCarrierPlaceholder')" />
    </div>
    <label v-if="!props.shippingForm.shipped" class="flex items-center gap-2 text-sm">
      <Checkbox v-model="shippingForm.mark_shipped" />
      {{ t('admin.genericShow.markShipped') }}
    </label>
    <Button type="submit" size="sm" :disabled="shippingForm.processing">{{ t('admin.genericShow.saveShipping') }}</Button>
  </form>

  <form v-if="props.staffNoteForm" class="mt-6 max-w-lg space-y-3 rounded-lg border p-4" @submit.prevent="submitStaffNote">
    <h2 class="text-sm font-semibold">{{ t('admin.genericShow.staffNote') }}</h2>
    <p class="text-xs text-muted-foreground">{{ t('admin.genericShow.staffNoteHint') }}</p>
    <div class="space-y-2">
      <Label>{{ t('admin.genericShow.noteBody') }}</Label>
      <Input v-model="staffNoteForm.body" :placeholder="t('admin.genericShow.notePlaceholder')" required />
    </div>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="staffNoteForm.visible_to_customer" />
      {{ t('admin.genericShow.visibleToBuyer') }}
    </label>
    <Button type="submit" size="sm" :disabled="staffNoteForm.processing">{{ t('admin.genericShow.saveNote') }}</Button>
  </form>

  <form v-if="props.storeCreditForm" class="mt-6 max-w-lg space-y-3 rounded-lg border p-4" @submit.prevent="submitStoreCredit">
    <h2 class="text-sm font-semibold">{{ t('admin.genericShow.storeCredit') }}</h2>
    <p class="text-xs text-muted-foreground">{{ t('admin.genericShow.currentBalance', { balance: props.storeCreditForm.balance_label }) }}</p>
    <div class="space-y-2">
      <Label>{{ t('admin.genericShow.adjustCents') }}</Label>
      <Input v-model.number="storeCreditForm.amount_cents" type="number" required />
    </div>
    <div class="space-y-2">
      <Label>{{ t('admin.genericShow.note') }}</Label>
      <Input v-model="storeCreditForm.note" :placeholder="t('admin.common.optional')" />
    </div>
    <Button type="submit" size="sm" :disabled="storeCreditForm.processing">{{ t('admin.genericShow.saveBalance') }}</Button>
  </form>

  <div v-if="props.silenceForm" class="mt-6 max-w-lg space-y-3 rounded-lg border p-4">
    <h2 class="text-sm font-semibold">{{ t('admin.genericShow.silence') }}</h2>
    <p class="text-xs text-muted-foreground">{{ t('admin.genericShow.silenceHint') }}</p>
    <p v-if="props.silenceForm.silenced" class="text-sm text-amber-700">{{ t('admin.genericShow.silencedNotice') }}</p>
    <form v-if="!props.silenceForm.silenced" class="space-y-3" @submit.prevent="submitSilence">
      <div class="space-y-2">
        <Label>{{ t('admin.common.reason') }}</Label>
        <Input v-model="silenceForm.reason" :placeholder="t('admin.common.optional')" />
      </div>
      <div class="space-y-2">
        <Label>{{ t('admin.genericShow.days') }}</Label>
        <Input v-model.number="silenceForm.days" type="number" min="1" :placeholder="t('admin.genericShow.daysPlaceholder')" />
      </div>
      <Button type="submit" variant="destructive" size="sm" :disabled="silenceForm.processing">{{ t('admin.genericShow.applySilence') }}</Button>
    </form>
    <Button v-else type="button" variant="outline" size="sm" @click="submitUnsilence">{{ t('admin.genericShow.removeSilence') }}</Button>
  </div>

  <form v-if="props.trustLevelForm" class="mt-6 max-w-lg space-y-3 rounded-lg border p-4" @submit.prevent="submitTrustLevel">
    <h2 class="text-sm font-semibold">{{ t('admin.genericShow.trustLevel') }}</h2>
    <p class="text-xs text-muted-foreground">{{ t('admin.genericShow.currentTrust', { level: props.trustLevelForm.current_level }) }}</p>
    <div class="space-y-2">
      <Label>{{ t('admin.genericShow.manualOverride') }}</Label>
      <Select v-model="trustLevelOverride" :options="trustLevelOptions" block />
    </div>
    <Button type="submit" size="sm">{{ t('admin.genericShow.saveTrust') }}</Button>
  </form>

  <div class="mt-6 flex flex-wrap justify-end gap-3 sm:justify-start">
    <template v-for="action in actions" :key="action.href + action.label">
      <Button
        v-if="action.method && action.method !== 'get'"
        type="button"
        :variant="action.variant ?? 'default'"
        @click="runAction(action)"
      >
        {{ action.label }}
      </Button>
      <Button
        v-else-if="action.confirm"
        type="button"
        :variant="action.variant ?? 'outline'"
        @click="runAction(action)"
      >
        {{ action.label }}
      </Button>
      <Button v-else as-child :variant="action.variant ?? 'outline'">
        <Link :href="action.href">{{ action.label }}</Link>
      </Button>
    </template>
    <Button as-child variant="outline">
      <Link :href="backUrl">{{ t('admin.genericShow.back') }}</Link>
    </Button>
  </div>
</template>
