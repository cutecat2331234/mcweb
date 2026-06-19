<script setup lang="ts">
import { ref, computed } from 'vue'
import { Link, router, useForm } from '@inertiajs/vue3'
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
  silenceForm?: SilenceForm | null
  trustLevelForm?: TrustLevelForm | null
  storeCreditForm?: StoreCreditForm | null
  backUrl: string
}>()

const trustLevelOverride = ref(props.trustLevelForm?.override?.toString() ?? 'auto')

const badgeSlug = ref('')

const badgeOptions = computed(() => [
  { value: '', label: '请选择' },
  ...(props.badgeForm?.badges || []).map((badge) => ({ value: badge.slug, label: badge.name })),
])

const trustLevelOptions = computed(() => [
  { value: 'auto', label: '自动（按发帖数计算）' },
  ...(props.trustLevelForm?.levels || []).map((level) => ({ value: String(level.value), label: level.label })),
])

const warningForm = useForm({
  reason: '',
  points: 1,
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

async function runAction(action: DetailAction) {
  if (action.confirm) {
    const ok = await confirm({
      title: '确认操作',
      message: action.confirm,
      confirmLabel: '继续',
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

function submitBadge() {
  if (!props.badgeForm || !badgeSlug.value) return
  router.post(props.badgeForm.action_url, { badge_slug: badgeSlug.value })
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
    <h2 class="text-sm font-semibold">禁言用户</h2>
    <div class="space-y-2">
      <Label>原因</Label>
      <Input v-model="muteForm.reason" placeholder="禁言原因" />
    </div>
    <div class="space-y-2">
      <Label>到期时间（空=永久）</Label>
      <Input v-model="muteForm.expires_at" type="datetime-local" />
    </div>
    <Button type="submit" variant="destructive" size="sm" :disabled="muteForm.processing">禁言</Button>
  </form>

  <form v-if="props.banForm && !props.banForm.banned" class="mt-6 max-w-lg space-y-3 rounded-lg border p-4" @submit.prevent="submitBan">
    <h2 class="text-sm font-semibold">封禁用户</h2>
    <div class="space-y-2">
      <Label>封禁原因</Label>
      <Input v-model="banForm.reason" placeholder="封禁原因" />
    </div>
    <div class="space-y-2">
      <Label>到期时间（空=永久）</Label>
      <Input v-model="banForm.expires_at" type="datetime-local" />
    </div>
    <Button type="submit" variant="destructive" size="sm" :disabled="banForm.processing">封禁账号</Button>
  </form>

  <div v-if="props.banForm?.banned" class="mt-6 max-w-lg rounded-lg border p-4">
    <p class="mb-3 text-sm text-destructive">该用户当前处于封禁状态。</p>
    <Button type="button" size="sm" variant="outline" @click="submitUnban">解除封禁</Button>
  </div>

  <form v-if="props.refundForm" class="mt-6 max-w-lg space-y-3 rounded-lg border p-4" @submit.prevent="submitRefund">
    <h2 class="text-sm font-semibold">部分退款</h2>
    <p class="text-xs text-muted-foreground">最多可退 {{ props.refundForm.max_label }}</p>
    <div class="space-y-2">
      <Label>退款金额（分）</Label>
      <Input v-model.number="refundForm.amount_cents" type="number" :max="props.refundForm.max_cents" min="1" required />
    </div>
    <div class="space-y-2">
      <Label>原因</Label>
      <Input v-model="refundForm.reason" placeholder="退款原因" />
    </div>
    <Button type="submit" size="sm" :disabled="refundForm.processing">处理退款</Button>
  </form>

  <form v-if="props.badgeForm" class="mt-6 max-w-lg space-y-3 rounded-lg border p-4" @submit.prevent="submitBadge">
    <h2 class="text-sm font-semibold">授予徽章</h2>
    <p v-if="props.badgeForm.earned.length" class="text-xs text-muted-foreground">已拥有：{{ props.badgeForm.earned.join('、') }}</p>
    <div class="space-y-2">
      <Label>选择徽章</Label>
      <Select v-model="badgeSlug" :options="badgeOptions" block />
    </div>
    <Button type="submit" size="sm">授予</Button>
  </form>

  <form v-if="props.warningForm" class="mt-6 max-w-lg space-y-3 rounded-lg border p-4" @submit.prevent="submitWarning">
    <h2 class="text-sm font-semibold">发出警告（XenForo）</h2>
    <p class="text-xs text-muted-foreground">当前累计警告积分：{{ props.warningForm.warning_points }}</p>
    <div class="space-y-2">
      <Label>警告原因</Label>
      <Input v-model="warningForm.reason" placeholder="说明违规原因" required />
    </div>
    <div class="space-y-2">
      <Label>警告点数（1-10）</Label>
      <Input v-model.number="warningForm.points" type="number" min="1" max="10" />
    </div>
    <Button type="submit" variant="destructive" size="sm" :disabled="warningForm.processing">发出警告</Button>
  </form>

  <form v-if="props.staffNoteForm" class="mt-6 max-w-lg space-y-3 rounded-lg border p-4" @submit.prevent="submitStaffNote">
    <h2 class="text-sm font-semibold">添加员工备注</h2>
    <p class="text-xs text-muted-foreground">默认仅管理员可见；勾选后买家可在订单页查看。</p>
    <div class="space-y-2">
      <Label>备注内容</Label>
      <Input v-model="staffNoteForm.body" placeholder="内部备注" required />
    </div>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="staffNoteForm.visible_to_customer" />
      对买家可见
    </label>
    <Button type="submit" size="sm" :disabled="staffNoteForm.processing">保存备注</Button>
  </form>

  <form v-if="props.storeCreditForm" class="mt-6 max-w-lg space-y-3 rounded-lg border p-4" @submit.prevent="submitStoreCredit">
    <h2 class="text-sm font-semibold">调整商店余额</h2>
    <p class="text-xs text-muted-foreground">当前余额：{{ props.storeCreditForm.balance_label }}</p>
    <div class="space-y-2">
      <Label>调整金额（分，正数增加负数扣减）</Label>
      <Input v-model.number="storeCreditForm.amount_cents" type="number" required />
    </div>
    <div class="space-y-2">
      <Label>备注</Label>
      <Input v-model="storeCreditForm.note" placeholder="可选" />
    </div>
    <Button type="submit" size="sm" :disabled="storeCreditForm.processing">保存余额</Button>
  </form>

  <div v-if="props.silenceForm" class="mt-6 max-w-lg space-y-3 rounded-lg border p-4">
    <h2 class="text-sm font-semibold">用户沉默（XenForo）</h2>
    <p class="text-xs text-muted-foreground">沉默用户可浏览论坛但无法发帖或回复，与封禁不同。</p>
    <p v-if="props.silenceForm.silenced" class="text-sm text-amber-700">当前处于沉默状态。</p>
    <form v-if="!props.silenceForm.silenced" class="space-y-3" @submit.prevent="submitSilence">
      <div class="space-y-2">
        <Label>原因</Label>
        <Input v-model="silenceForm.reason" placeholder="可选" />
      </div>
      <div class="space-y-2">
        <Label>天数（留空为永久）</Label>
        <Input v-model.number="silenceForm.days" type="number" min="1" placeholder="例如 7" />
      </div>
      <Button type="submit" variant="destructive" size="sm" :disabled="silenceForm.processing">施加沉默</Button>
    </form>
    <Button v-else type="button" variant="outline" size="sm" @click="submitUnsilence">解除沉默</Button>
  </div>

  <form v-if="props.trustLevelForm" class="mt-6 max-w-lg space-y-3 rounded-lg border p-4" @submit.prevent="submitTrustLevel">
    <h2 class="text-sm font-semibold">论坛信任等级覆盖（Discourse TL）</h2>
    <p class="text-xs text-muted-foreground">当前有效等级：TL{{ props.trustLevelForm.current_level }}</p>
    <div class="space-y-2">
      <Label>手动覆盖</Label>
      <Select v-model="trustLevelOverride" :options="trustLevelOptions" block />
    </div>
    <Button type="submit" size="sm">保存信任等级</Button>
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
      <Link :href="backUrl">返回</Link>
    </Button>
  </div>
</template>
