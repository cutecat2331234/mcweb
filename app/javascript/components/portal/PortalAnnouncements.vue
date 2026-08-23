<script setup lang="ts">
import { computed, ref } from 'vue'
import { Alert, Space, TypographyText } from '@mcweb/ui'
import { useI18n } from 'vue-i18n'

import { csrfHeaders } from '@/lib/csrf'
import { frontendApplicationRequestHeaders } from '@/lib/frontendApplications'
import { routes } from '@/lib/routes'

type GlobalAnnouncement = {
  id: string
  title: string
  url: string
}

type ForumNotice = {
  id: number
  title: string
  message_html: string
  style: string
  dismissible: boolean
  dismiss_url: string
}

const props = defineProps<{
  authenticated: boolean
  announcements?: GlobalAnnouncement[]
  notices?: ForumNotice[]
}>()

const { t } = useI18n()
const dismissedAnnouncementIds = ref<string[]>(readDismissedAnnouncementIds())
const dismissedNoticeIds = ref<number[]>([])
const visibleAnnouncements = computed(() => (props.announcements ?? [])
  .filter((item) => !dismissedAnnouncementIds.value.includes(item.id)))
const visibleNotices = computed(() => (props.notices ?? [])
  .filter((notice) => !dismissedNoticeIds.value.includes(notice.id)))

function readDismissedAnnouncementIds(): string[] {
  if (typeof window === 'undefined') return []
  try {
    const value = JSON.parse(window.localStorage.getItem('mc-dismissed-announcements') || '[]')
    return Array.isArray(value) ? value.filter((item): item is string => typeof item === 'string') : []
  } catch {
    return []
  }
}

function persistDismissedAnnouncementIds() {
  try {
    window.localStorage.setItem(
      'mc-dismissed-announcements',
      JSON.stringify(dismissedAnnouncementIds.value),
    )
  } catch {
    // Local dismissal remains effective for this page when storage is unavailable.
  }
}

async function postDismissal(url: string, data?: Record<string, string>) {
  const headers: Record<string, string> = {
    ...csrfHeaders(),
    ...frontendApplicationRequestHeaders('forum'),
  }
  if (data) headers['Content-Type'] = 'application/json'

  try {
    await fetch(url, {
      method: 'POST',
      headers,
      credentials: 'same-origin',
      body: data ? JSON.stringify(data) : undefined,
    })
  } catch (error) {
    console.warn('[McWeb] dismissal could not be persisted', error)
  }
}

function dismissAnnouncements() {
  const items = visibleAnnouncements.value
  dismissedAnnouncementIds.value = [
    ...new Set([...dismissedAnnouncementIds.value, ...items.map((item) => item.id)]),
  ]
  persistDismissedAnnouncementIds()
  if (!props.authenticated) return

  for (const item of items) {
    void postDismissal(routes.forumDismissAnnouncements, { topic_id: item.id })
  }
}

function dismissNotice(notice: ForumNotice) {
  dismissedNoticeIds.value = [...new Set([...dismissedNoticeIds.value, notice.id])]
  if (props.authenticated && notice.dismissible) void postDismissal(notice.dismiss_url)
}

function noticeType(style: string): 'info' | 'success' | 'warning' | 'error' {
  if (style === 'success' || style === 'warning') return style
  return style === 'danger' ? 'error' : 'info'
}
</script>

<template>
  <div
    v-if="visibleAnnouncements.length || visibleNotices.length"
    class="mc-portal-announcements"
    :style="{ padding: '12px 20px 0' }"
  >
    <Space direction="vertical" fill :size="8">
      <Alert
        v-if="visibleAnnouncements.length"
        type="warning"
        :title="t('common.announcement')"
        show-icon
        closable
        @close="dismissAnnouncements"
      >
        <Space wrap :size="12">
          <a v-for="item in visibleAnnouncements" :key="item.id" :href="item.url">
            <TypographyText>{{ item.title }}</TypographyText>
          </a>
        </Space>
      </Alert>

      <Alert
        v-for="notice in visibleNotices"
        :key="notice.id"
        :type="noticeType(notice.style)"
        :title="notice.title"
        :closable="notice.dismissible"
        show-icon
        @close="dismissNotice(notice)"
      >
        <div v-html="notice.message_html" />
      </Alert>
    </Space>
  </div>
</template>
