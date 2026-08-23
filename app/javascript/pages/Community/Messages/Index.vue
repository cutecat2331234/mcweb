<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import {
  Avatar,
  Button,
  Card,
  Empty,
  Input,
  List,
  ListItem,
  Space,
  Tag,
  TypographyText,
} from '@mcweb/ui'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
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
    starred?: boolean
    star_url?: string
    label?: string | null
  }>
  conversationInvitations?: Array<{
    public_id: string
    title: string
    inviter: string
    expires_at: string
    accept_url: string
    decline_url: string
  }>
  showArchived?: boolean
  archivedToggleUrl?: string
  showStarred?: boolean
  starredToggleUrl?: string
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
const respondingInvitationId = ref<string | null>(null)

function searchMessages() {
  router.get(routes.forumMessages, {
    q: searchQuery.value || undefined,
    archived: props.showArchived ? '1' : undefined,
    starred: props.showStarred ? '1' : undefined,
  }, { preserveState: true })
}

function toggleStar(conv: { star_url?: string }) {
  if (!conv.star_url) return
  router.post(conv.star_url, {}, { preserveScroll: true, preserveState: true })
}

function visit(url: string | undefined) {
  if (!url) return
  router.visit(url)
}

function respondToInvitation(publicId: string, url: string) {
  respondingInvitationId.value = publicId
  router.post(url, {}, {
    preserveScroll: true,
    onFinish: () => {
      respondingInvitationId.value = null
    },
  })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('forum.messages.title'), current: true },
  ]" />

  <div class="mb-4 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
    <PageHeader :title="t('forum.messages.title')" :subtitle="showArchived ? t('forum.messages.subtitleArchived') : t('forum.messages.subtitleActive')" />
    <Space wrap>
      <Button
        v-if="starredToggleUrl"
        html-type="button"
        size="small"
        :type="showStarred ? 'primary' : 'outline'"
        @click="visit(starredToggleUrl)"
      >
        {{ showStarred ? t('forum.messages.allMessages') : t('forum.messages.starred') }}
      </Button>
      <Button
        v-if="archivedToggleUrl"
        html-type="button"
        size="small"
        type="outline"
        @click="visit(archivedToggleUrl)"
      >
        {{ showArchived ? t('forum.messages.backToActive') : t('forum.messages.viewArchived') }}
      </Button>
      <Button html-type="button" size="small" type="primary" @click="visit(routes.forumMessagesNew)">
        {{ t('forum.messages.newMessage') }}
      </Button>
      <Button html-type="button" size="small" type="outline" @click="visit(routes.forumMessagesGroupNew)">
        {{ t('forum.messages.group') }}
      </Button>
    </Space>
  </div>

  <Card
    v-if="conversationInvitations?.length"
    id="conversation-invitations"
    class="mb-4"
    :aria-label="t('forum.messages.pendingInvitations')"
  >
    <template #title>
      <Space direction="vertical" size="mini">
        <TypographyText strong>{{ t('forum.messages.pendingInvitations') }}</TypographyText>
        <TypographyText type="secondary">{{ t('forum.messages.pendingInvitationsHint') }}</TypographyText>
      </Space>
    </template>
    <List :data="conversationInvitations" :bordered="false" size="small">
      <template #item="{ item }">
        <ListItem>
          <div class="flex w-full flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <Space direction="vertical" size="mini">
              <TypographyText strong>{{ item.title }}</TypographyText>
              <TypographyText type="secondary">
                {{ t('forum.messages.invitedBy', { username: item.inviter }) }}
                · {{ t('forum.messages.invitationExpires', { time: item.expires_at }) }}
              </TypographyText>
            </Space>
            <Space wrap>
              <Button
                html-type="button"
                size="small"
                type="primary"
                :loading="respondingInvitationId === item.public_id"
                :disabled="respondingInvitationId !== null"
                @click="respondToInvitation(item.public_id, item.accept_url)"
              >
                {{ t('forum.messages.acceptInvitation') }}
              </Button>
              <Button
                html-type="button"
                size="small"
                type="outline"
                :disabled="respondingInvitationId !== null"
                @click="respondToInvitation(item.public_id, item.decline_url)"
              >
                {{ t('forum.messages.declineInvitation') }}
              </Button>
            </Space>
          </div>
        </ListItem>
      </template>
    </List>
  </Card>

  <form class="mb-4 flex max-w-md gap-2" @submit.prevent="searchMessages">
    <Input v-model="searchQuery" :placeholder="t('forum.messages.searchPlaceholder')" allow-clear class="flex-1" />
    <Button html-type="submit" type="outline">{{ t('forum.messages.search') }}</Button>
  </form>

  <List v-if="conversations.length" :data="conversations" bordered>
    <template #item="{ item }">
      <ListItem>
        <Link :href="item.url" class="flex min-w-0 flex-1 items-center gap-3 no-underline">
          <Avatar :size="40" :image-url="item.avatar_url" :aria-label="item.other_username" />
          <Space direction="vertical" size="mini" class="min-w-0 flex-1">
            <div class="flex items-center justify-between gap-2">
              <Space size="mini" wrap>
                <TypographyText strong>{{ item.display_name || item.other_username }}</TypographyText>
                <Tag v-if="item.label" size="small">{{ item.label }}</Tag>
              </Space>
              <TypographyText type="secondary">{{ item.last_message_at || '' }}</TypographyText>
            </div>
            <TypographyText type="secondary" ellipsis>
              {{ item.last_message_preview || t('forum.messages.noMessages') }}
            </TypographyText>
          </Space>
          <Tag v-if="item.unread_count > 0" color="arcoblue">{{ item.unread_count }}</Tag>
        </Link>
        <Button
          v-if="item.star_url"
          html-type="button"
          type="text"
          size="mini"
          :status="item.starred ? 'warning' : 'normal'"
          :title="item.starred ? t('forum.messages.unstar') : t('forum.messages.star')"
          :aria-label="item.starred ? t('forum.messages.unstar') : t('forum.messages.star')"
          @click="toggleStar(item)"
        >
          {{ item.starred ? '★' : '☆' }}
        </Button>
      </ListItem>
    </template>
  </List>
  <Empty v-else :description="t('forum.messages.empty')" />

  <Pagination v-if="pagination && pagination.pages > 1" :meta="pagination" class="mt-4" />
</template>
