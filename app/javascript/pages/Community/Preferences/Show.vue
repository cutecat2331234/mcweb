<script setup lang="ts">
import { Link, router, useForm } from '@inertiajs/vue3'
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import LanguageSwitcher from '@/components/portal/LanguageSwitcher.vue'
import Input from '@/components/ui/Input.vue'
import Button from '@/components/ui/Button.vue'
import Label from '@/components/ui/Label.vue'
import Select from '@/components/ui/Select.vue'
import Checkbox from '@/components/ui/Checkbox.vue'
import { routes } from '@/lib/routes'
import { readCsrfToken } from '@/lib/csrf'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

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
  watch_email_mode: string
  watch_email_mode_options: Array<{ value: string; label: string }>
  dnd_active?: boolean
  dnd_until?: string | null
  notificationLevelGuide?: Array<{ value: string; label: string; description: string }>
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
  watch_email_mode: props.watch_email_mode,
})

const togglingId = ref<number | null>(null)
const editingSearchId = ref<number | null>(null)
const editingSearchName = ref('')
const renamingSearchId = ref<number | null>(null)

function submit() {
  form.patch(routes.forumPreferences)
}

function pauseDnd(minutes: number) {
  router.patch(routes.forumPreferences, { dnd_minutes: minutes }, { preserveScroll: true })
}

function retryWebhook(url: string) {
  router.post(url, {}, { preserveScroll: true, onSuccess: () => router.reload({ only: ['savedSearchWebhookDeliveries'] }) })
}

async function toggleSavedSearchNotify(search: SavedSearchItem) {
  togglingId.value = search.id
  try {
    const token = readCsrfToken()
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
  const token = readCsrfToken()
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
    const token = readCsrfToken()
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
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('preferences.title'), current: true },
  ]" />

  <PageHeader :title="t('preferences.title')" :subtitle="t('preferences.subtitle')" />

  <section class="mb-6 max-w-lg rounded-lg border p-4">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h2 class="text-sm font-medium">{{ t('preferences.language') }}</h2>
        <p class="mt-1 text-sm text-muted-foreground">{{ t('preferences.languageHint') }}</p>
      </div>
      <LanguageSwitcher />
    </div>
  </section>

  <section class="mb-6 max-w-lg rounded-lg border p-4">
    <h2 class="text-sm font-semibold">{{ t('preferences.dnd.title') }}</h2>
    <p v-if="dnd_active" class="mt-1 text-sm text-muted-foreground">{{ t('preferences.dnd.activeUntil', { time: dnd_until }) }}</p>
    <p v-else class="mt-1 text-sm text-muted-foreground">{{ t('preferences.dnd.description') }}</p>
    <div class="mt-3 flex flex-wrap gap-2">
      <Button type="button" size="sm" variant="outline" @click="pauseDnd(60)">{{ t('preferences.dnd.pause1h') }}</Button>
      <Button type="button" size="sm" variant="outline" @click="pauseDnd(480)">{{ t('preferences.dnd.pause8h') }}</Button>
      <Button type="button" size="sm" variant="outline" @click="pauseDnd(1440)">{{ t('preferences.dnd.pause24h') }}</Button>
      <Button v-if="dnd_active" type="button" size="sm" @click="pauseDnd(0)">{{ t('preferences.dnd.resume') }}</Button>
    </div>
  </section>

  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <div
      v-for="pref in preferences"
      :key="pref.notification_type"
      class="rounded-lg border p-4"
    >
      <p class="mb-3 text-sm font-medium">{{ pref.label }}</p>
      <div class="flex flex-wrap gap-6">
        <label class="flex items-center gap-2 text-sm">
          <Checkbox v-model="form.preferences[pref.notification_type].in_app" />
          {{ t('preferences.inApp') }}
        </label>
        <label class="flex items-center gap-2 text-sm">
          <Checkbox v-model="form.preferences[pref.notification_type].email" />
          {{ t('preferences.email') }}
        </label>
      </div>
    </div>

    <div class="rounded-lg border p-4">
      <Label for="watch-email-mode" class="mb-2 block text-sm font-medium">{{ t('preferences.watchEmailMode') }}</Label>
      <Select
        id="watch-email-mode"
        v-model="form.watch_email_mode"
        :options="watch_email_mode_options"
        class="w-full"
      />
      <p class="mt-2 text-xs text-muted-foreground">{{ t('preferences.watchEmailModeHint') }}</p>
    </div>

    <div v-if="notificationLevelGuide?.length" class="rounded-lg border p-4">
      <p class="mb-3 text-sm font-medium">{{ t('preferences.notificationLevelGuide') }}</p>
      <ul class="space-y-2 text-sm text-muted-foreground">
        <li v-for="item in notificationLevelGuide" :key="item.value">
          <span class="font-medium text-foreground">{{ item.label }}</span> — {{ item.description }}
        </li>
      </ul>
    </div>

    <div class="rounded-lg border p-4">
      <Label for="digest" class="mb-2 block text-sm font-medium">{{ t('preferences.digest') }}</Label>
      <Select
        id="digest"
        v-model="form.digest_frequency"
        :options="digest_options"
        class="w-full"
      />
      <p class="mt-2 text-xs text-muted-foreground">{{ t('preferences.digestHint') }}</p>
      <label v-if="form.digest_frequency !== 'none'" class="mt-3 flex items-center gap-2 text-sm">
        <Checkbox v-model="form.digest_watched_only" />
        {{ t('preferences.digestWatchedOnly') }}
      </label>
    </div>

    <Button type="submit" :disabled="form.processing">{{ t('preferences.save') }}</Button>
  </form>

  <section v-if="savedSearches?.length" class="mt-8 max-w-lg">
    <div class="mb-3 flex flex-wrap items-center justify-between gap-2">
      <h2 class="text-sm font-semibold">{{ t('preferences.savedSearchesTitle') }}</h2>
      <a
        v-if="savedSearchesOpmlUrl"
        :href="savedSearchesOpmlUrl"
        class="text-xs text-primary hover:underline"
        target="_blank"
        rel="noopener noreferrer"
      >
        {{ t('preferences.exportOpml') }}
      </a>
    </div>
    <p class="mb-4 text-xs text-muted-foreground">{{ t('preferences.savedSearchesHint') }}</p>
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
              <Button type="button" size="sm" variant="outline" :disabled="renamingSearchId === search.id" @click="saveRenameSearch(search)">{{ t('common.save') }}</Button>
              <Button type="button" size="sm" variant="ghost" @click="cancelRenameSearch">{{ t('common.cancel') }}</Button>
            </div>
          </template>
          <template v-else>
            <Link :href="search.url" class="font-medium hover:underline">{{ search.name }}</Link>
            <button type="button" class="ml-2 text-xs text-muted-foreground hover:text-foreground" :title="t('preferences.rename')" @click="startRenameSearch(search)">✎</button>
          </template>
          <p v-if="search.query && editingSearchId !== search.id" class="truncate text-xs text-muted-foreground">{{ t('preferences.keywords') }}{{ t('common.colon') }}{{ search.query }}</p>
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
            <Checkbox
              :model-value="search.notify_daily"
              :disabled="togglingId === search.id"
              @update:model-value="toggleSavedSearchNotify(search)"
            />
            {{ t('preferences.dailyEmail') }}
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
          <span v-if="search.webhook_url" class="text-xs text-muted-foreground" :title="t('preferences.webhookConfigured')">Webhook</span>
          <button
            type="button"
            class="text-xs text-destructive hover:underline"
            @click="deleteSavedSearch(search.delete_url)"
          >
            {{ t('preferences.delete') }}
          </button>
        </div>
      </li>
    </ul>
    <p class="mt-3 text-xs text-muted-foreground">
      <Link :href="routes.forumSearch" class="text-primary hover:underline">{{ t('preferences.goToSearch') }}</Link>
      {{ t('preferences.manageSavedSearches') }}
      <template v-if="savedSearchesOpmlUrl">
        ·
        <a :href="savedSearchesOpmlUrl" class="text-primary hover:underline" target="_blank" rel="noopener noreferrer">{{ t('preferences.exportSavedSearchesOpml') }}</a>
      </template>
      <template v-if="watchingOpmlUrl">
        ·
        <a :href="watchingOpmlUrl" class="text-primary hover:underline" target="_blank" rel="noopener noreferrer">{{ t('preferences.exportWatchingOpml') }}</a>
      </template>
    </p>
  </section>

  <section v-if="savedSearchWebhookDeliveries?.length" class="mt-8 max-w-lg">
    <h2 class="mb-3 text-sm font-semibold">{{ t('preferences.webhookDeliveriesTitle') }}</h2>
    <ul class="space-y-2 text-xs">
      <li
        v-for="delivery in savedSearchWebhookDeliveries"
        :key="delivery.id"
        class="rounded-lg border px-3 py-2"
      >
        <span class="font-medium">{{ delivery.search_name || t('preferences.searchFallback') }}</span>
        — {{ delivery.status }}
        <span v-if="delivery.response_code" class="text-muted-foreground">({{ delivery.response_code }})</span>
        <span class="ml-2 text-muted-foreground">{{ delivery.created_at }}</span>
        <button
          v-if="delivery.retry_url"
          type="button"
          class="mt-1 block text-xs text-primary hover:underline"
          @click="retryWebhook(delivery.retry_url)"
        >
          {{ t('preferences.retrySend') }}
        </button>
      </li>
    </ul>
  </section>
</template>
