<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Badge from '@/components/ui/Badge.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Pagination from '@/components/portal/Pagination.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

const props = defineProps<{
  conversations: Array<{
    id: number
    url: string
    is_group?: boolean
    display_name?: string
    other_username: string
    avatar_url: string
    last_message_at: string | null
    last_message_preview: string | null
    unread_count: number
    archived?: boolean
  }>
  showArchived?: boolean
  archivedToggleUrl?: string
  query?: string
  pagination?: {
    page: number
    pages: number
    count: number
    prev: number | null
    next: number | null
  }
}>()

const searchQuery = ref(props.query || '')

function searchMessages() {
  router.get(routes.forumMessages, {
    q: searchQuery.value || undefined,
    archived: props.showArchived ? '1' : undefined,
  }, { preserveState: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('forum.messages.title'), current: true },
  ]" />

  <div class="mb-4 flex items-center justify-between">
    <PageHeader :title="t('forum.messages.title')" :subtitle="showArchived ? t('forum.messages.subtitleArchived') : t('forum.messages.subtitleActive')" />
    <div class="flex gap-2">
      <Button v-if="archivedToggleUrl" as-child size="sm" variant="outline">
        <Link :href="archivedToggleUrl">{{ showArchived ? t('forum.messages.backToActive') : t('forum.messages.viewArchived') }}</Link>
      </Button>
      <Button as-child size="sm">
        <Link :href="routes.forumMessagesNew">{{ t('forum.messages.newMessage') }}</Link>
      </Button>
      <Button as-child size="sm" variant="outline">
        <Link :href="routes.forumMessagesGroupNew">{{ t('forum.messages.group') }}</Link>
      </Button>
    </div>
  </div>

  <form class="mb-4 flex max-w-md gap-2" @submit.prevent="searchMessages">
    <Input v-model="searchQuery" :placeholder="t('forum.messages.searchPlaceholder')" class="flex-1" />
    <Button type="submit" variant="outline">{{ t('forum.messages.search') }}</Button>
  </form>

  <div v-if="conversations.length" class="divide-y rounded-lg border">
    <Link
      v-for="conv in conversations"
      :key="conv.id"
      :href="conv.url"
      class="flex items-center gap-3 p-4 no-underline hover:bg-muted/50"
    >
      <img :src="conv.avatar_url" :alt="conv.other_username" class="h-10 w-10 rounded-full" />
      <div class="min-w-0 flex-1">
        <div class="flex items-center justify-between gap-2">
          <span class="font-medium text-foreground">{{ conv.display_name || conv.other_username }}</span>
          <span class="text-xs text-muted-foreground">{{ conv.last_message_at || '' }}</span>
        </div>
        <p class="truncate text-sm text-muted-foreground">{{ conv.last_message_preview || t('forum.messages.noMessages') }}</p>
      </div>
      <Badge v-if="conv.unread_count > 0" variant="danger">{{ conv.unread_count }}</Badge>
    </Link>
  </div>
  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    {{ t('forum.messages.empty') }}
  </p>

  <Pagination v-if="pagination && pagination.pages > 1" :meta="pagination" class="mt-4" />
</template>
