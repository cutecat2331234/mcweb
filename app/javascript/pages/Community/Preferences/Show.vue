<script setup lang="ts">
import { Link, router, useForm } from '@inertiajs/vue3'
import { ref } from 'vue'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Input from '@/components/ui/Input.vue'
import Button from '@/components/ui/Button.vue'
import Label from '@/components/ui/Label.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

export interface SavedSearchItem {
  id: number
  name: string
  query: string
  notify_daily: boolean
  url: string
  rss_url?: string
  webhook_url?: string | null
  filter_labels?: string[]
  update_url: string
  delete_url: string
}

const props = defineProps<{
  preferences: Array<{
    notification_type: string
    label: string
    in_app: boolean
    email: boolean
  }>
  digest_frequency: string
  digest_watched_only?: boolean
  digest_options: Array<{ value: string; label: string }>
  savedSearches?: SavedSearchItem[]
  savedSearchesOpmlUrl?: string | null
  watchingOpmlUrl?: string | null
  savedSearchWebhookDeliveries?: Array<{
    id: number
    search_name: string | null
    event_type: string
    status: string
    response_code: number | null
    created_at: string
    retry_url?: string | null
  }>
}>()

const form = useForm({
  preferences: Object.fromEntries(
    props.preferences.map((pref) => [
      pref.notification_type,
      { in_app: pref.in_app, email: pref.email },
    ])
  ) as Record<string, { in_app: boolean; email: boolean }>,
  digest_frequency: props.digest_frequency,
  digest_watched_only: props.digest_watched_only ?? false,
})

const togglingId = ref<number | null>(null)
const editingSearchId = ref<number | null>(null)
const editingSearchName = ref('')
const renamingSearchId = ref<number | null>(null)

function submit() {
  form.patch(routes.forumPreferences)
}

function retryWebhook(url: string) {
  router.post(url, {}, { preserveScroll: true, onSuccess: () => router.reload({ only: ['savedSearchWebhookDeliveries'] }) })
}

async function toggleSavedSearchNotify(search: SavedSearchItem) {
  togglingId.value = search.id
  try {
    const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content || ''
    const response = await fetch(search.update_url, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        'X-CSRF-Token': token,
      },
      credentials: 'same-origin',
      body: JSON.stringify({
        saved_search: { notify_daily: !search.notify_daily },
      }),
    })
    if (response.ok) {
      router.reload({ only: ['savedSearches'] })
    }
  } finally {
    togglingId.value = null
  }
}

async function deleteSavedSearch(deleteUrl: string) {
  const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content || ''
  await fetch(deleteUrl, {
    method: 'DELETE',
    headers: { 'X-CSRF-Token': token, Accept: 'application/json' },
    credentials: 'same-origin',
  })
  router.reload({ only: ['savedSearches'] })
}

function startRenameSearch(search: SavedSearchItem) {
  editingSearchId.value = search.id
  editingSearchName.value = search.name
}

function cancelRenameSearch() {
  editingSearchId.value = null
  editingSearchName.value = ''
}

async function saveRenameSearch(search: SavedSearchItem) {
  if (!search.update_url || !editingSearchName.value.trim()) return
  renamingSearchId.value = search.id
  try {
    const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content || ''
    const response = await fetch(search.update_url, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        'X-CSRF-Token': token,
      },
      credentials: 'same-origin',
      body: JSON.stringify({
        saved_search: { name: editingSearchName.value.trim() },
      }),
    })
    if (response.ok) {
      editingSearchId.value = null
      editingSearchName.value = ''
      router.reload({ only: ['savedSearches'] })
    }
  } finally {
    renamingSearchId.value = null
  }
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '通知偏好', current: true },
  ]" />

  <PageHeader title="通知偏好" subtitle="管理站内通知与邮件通知" />

  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <div
      v-for="pref in preferences"
      :key="pref.notification_type"
      class="rounded-lg border p-4"
    >
      <p class="mb-3 text-sm font-medium">{{ pref.label }}</p>
      <div class="flex flex-wrap gap-6">
        <label class="flex items-center gap-2 text-sm">
          <input
            v-model="form.preferences[pref.notification_type].in_app"
            type="checkbox"
            class="h-4 w-4"
          />
          站内通知
        </label>
        <label class="flex items-center gap-2 text-sm">
          <input
            v-model="form.preferences[pref.notification_type].email"
            type="checkbox"
            class="h-4 w-4"
          />
          邮件通知
        </label>
      </div>
    </div>

    <div class="rounded-lg border p-4">
      <Label for="digest" class="mb-2 block text-sm font-medium">邮件摘要</Label>
      <select id="digest" v-model="form.digest_frequency" class="h-9 w-full rounded-md border px-2 text-sm">
        <option v-for="opt in digest_options" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
      </select>
      <p class="mt-2 text-xs text-muted-foreground">摘要将汇总未读的论坛通知，减少即时邮件打扰。</p>
      <label v-if="form.digest_frequency !== 'none'" class="mt-3 flex items-center gap-2 text-sm">
        <input v-model="form.digest_watched_only" type="checkbox">
        仅包含我关注的分区/主题/标签
      </label>
    </div>

    <Button type="submit" :disabled="form.processing">保存</Button>
  </form>

  <section v-if="savedSearches?.length" class="mt-8 max-w-lg">
    <div class="mb-3 flex flex-wrap items-center justify-between gap-2">
      <h2 class="text-sm font-semibold">保存的搜索与每日提醒</h2>
      <a
        v-if="savedSearchesOpmlUrl"
        :href="savedSearchesOpmlUrl"
        class="text-xs text-primary hover:underline"
        target="_blank"
        rel="noopener noreferrer"
      >
        导出 OPML
      </a>
    </div>
    <p class="mb-4 text-xs text-muted-foreground">开启后，当搜索条件匹配到新主题时，每天会收到一封邮件摘要（对标 Discourse 保存搜索提醒）。</p>
    <ul class="space-y-2">
      <li
        v-for="search in savedSearches"
        :key="search.id"
        class="flex flex-wrap items-center justify-between gap-2 rounded-lg border px-3 py-2 text-sm"
      >
        <div class="min-w-0 flex-1">
          <template v-if="editingSearchId === search.id">
            <div class="flex flex-wrap items-center gap-2">
              <Input
                v-model="editingSearchName"
                class="h-8 max-w-xs text-sm"
                @keydown.enter="saveRenameSearch(search)"
                @keydown.escape="cancelRenameSearch"
              />
              <Button type="button" size="sm" variant="outline" :disabled="renamingSearchId === search.id" @click="saveRenameSearch(search)">保存</Button>
              <Button type="button" size="sm" variant="ghost" @click="cancelRenameSearch">取消</Button>
            </div>
          </template>
          <template v-else>
            <Link :href="search.url" class="font-medium hover:underline">{{ search.name }}</Link>
            <button type="button" class="ml-2 text-xs text-muted-foreground hover:text-foreground" title="重命名" @click="startRenameSearch(search)">✎</button>
          </template>
          <p v-if="search.query && editingSearchId !== search.id" class="truncate text-xs text-muted-foreground">关键词：{{ search.query }}</p>
          <p v-if="search.filter_labels?.length && editingSearchId !== search.id" class="mt-1 flex flex-wrap gap-1">
            <span
              v-for="label in search.filter_labels"
              :key="label"
              class="rounded bg-muted px-1.5 py-0.5 text-[10px] text-muted-foreground"
            >
              {{ label }}
            </span>
          </p>
        </div>
        <div class="flex shrink-0 flex-wrap items-center gap-2">
          <label class="flex items-center gap-2 text-xs">
            <input
              type="checkbox"
              :checked="search.notify_daily"
              :disabled="togglingId === search.id"
              @change="toggleSavedSearchNotify(search)"
            />
            每日邮件
          </label>
          <a
            v-if="search.rss_url"
            :href="search.rss_url"
            class="text-xs text-primary hover:underline"
            target="_blank"
            rel="noopener noreferrer"
          >
            RSS
          </a>
          <span v-if="search.webhook_url" class="text-xs text-muted-foreground" title="已配置 Webhook">Webhook</span>
          <button
            type="button"
            class="text-xs text-destructive hover:underline"
            @click="deleteSavedSearch(search.delete_url)"
          >
            删除
          </button>
        </div>
      </li>
    </ul>
    <p class="mt-3 text-xs text-muted-foreground">
      <Link :href="routes.forumSearch" class="text-primary hover:underline">前往搜索页</Link>
      创建或管理更多保存的搜索。
      <template v-if="savedSearchesOpmlUrl">
        ·
        <a :href="savedSearchesOpmlUrl" class="text-primary hover:underline" target="_blank" rel="noopener noreferrer">导出保存搜索 OPML</a>
      </template>
      <template v-if="watchingOpmlUrl">
        ·
        <a :href="watchingOpmlUrl" class="text-primary hover:underline" target="_blank" rel="noopener noreferrer">导出关注订阅 OPML</a>
      </template>
    </p>
  </section>

  <section v-if="savedSearchWebhookDeliveries?.length" class="mt-8 max-w-lg">
    <h2 class="mb-3 text-sm font-semibold">保存搜索 Webhook 投递记录</h2>
    <ul class="space-y-2 text-xs">
      <li
        v-for="delivery in savedSearchWebhookDeliveries"
        :key="delivery.id"
        class="rounded-lg border px-3 py-2"
      >
        <span class="font-medium">{{ delivery.search_name || '搜索' }}</span>
        — {{ delivery.status }}
        <span v-if="delivery.response_code" class="text-muted-foreground">({{ delivery.response_code }})</span>
        <span class="ml-2 text-muted-foreground">{{ delivery.created_at }}</span>
        <button
          v-if="delivery.retry_url"
          type="button"
          class="mt-1 block text-xs text-primary hover:underline"
          @click="retryWebhook(delivery.retry_url)"
        >
          重试发送
        </button>
      </li>
    </ul>
  </section>
</template>
