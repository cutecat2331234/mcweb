<script setup lang="ts">
import { ref } from 'vue'
import { Link, router, useForm } from '@inertiajs/vue3'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Card from '@/components/ui/Card.vue'
import CardContent from '@/components/ui/CardContent.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'

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

const props = defineProps<{
  title: string
  subtitle?: string
  fields: DetailField[]
  sections?: DetailSection[]
  preformatted?: { title: string; content: string }
  actions?: DetailAction[]
  muteForm?: MuteForm | null
  banForm?: BanForm | null
  refundForm?: RefundForm | null
  badgeForm?: BadgeForm | null
  warningForm?: WarningForm | null
  backUrl: string
}>()

const badgeSlug = ref('')

const warningForm = useForm({
  reason: '',
  points: 1,
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
      <select v-model="badgeSlug" class="h-9 w-full rounded-md border px-2 text-sm" required>
        <option value="">请选择</option>
        <option v-for="badge in props.badgeForm.badges" :key="badge.slug" :value="badge.slug">{{ badge.name }}</option>
      </select>
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

  <div class="mt-6 flex flex-wrap gap-3">
    <template v-for="action in actions" :key="action.href + action.label">
      <Button
        v-if="action.method && action.method !== 'get'"
        as-child
        :variant="action.variant ?? 'default'"
      >
        <Link
          :href="action.href"
          :method="action.method"
          as="button"
          :data="action.data"
        >
          {{ action.label }}
        </Link>
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
