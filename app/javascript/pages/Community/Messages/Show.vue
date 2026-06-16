<script setup lang="ts">
import { ref } from 'vue'
import { Link, useForm, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import MarkdownEditor from '@/components/portal/MarkdownEditor.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  conversation: {
    id: number
    is_group?: boolean
    display_name?: string
    participants_label?: string
    other_user?: { username: string; avatar_url: string; profile_url: string }
  }
  messages: Array<{
    id: number
    body: string
    body_html: string
    author: string
    avatar_url: string
    is_mine: boolean
    created_at: string
    read_by?: string[]
  }>
  pagination: PaginationMeta
  participants: Array<{
    username: string
    avatar_url: string
    is_self?: boolean
    is_creator?: boolean
    remove_url?: string | null
  }>
  addParticipantUrl?: string | null
  archiveUrl?: string
  unarchiveUrl?: string
  archived?: boolean
  currentUsername?: string
}>()

const addUsername = ref('')

function addParticipant() {
  if (!props.addParticipantUrl || !addUsername.value.trim()) return
  router.post(props.addParticipantUrl, { username: addUsername.value.trim() }, {
    preserveScroll: true,
    onSuccess: () => { addUsername.value = '' },
  })
}

function removeParticipant(participant: { username: string; remove_url?: string | null; is_self?: boolean }) {
  if (!participant.remove_url) return
  const msg = participant.is_self ? '确定离开此群组？' : `确定移除 ${participant.username}？`
  if (!confirm(msg)) return
  router.delete(participant.remove_url, { preserveScroll: true })
}

const title = props.conversation.display_name || props.conversation.other_user?.username || '私信'
const subtitle = props.conversation.is_group ? props.conversation.participants_label : '私信对话'

const form = useForm({
  message: { body: '' },
})

function submit() {
  form.post(`/app/forum/conversations/${props.conversation.id}/messages`, {
    preserveScroll: true,
    onSuccess: () => { form.message.body = '' },
  })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '私信', href: routes.forumMessages },
    { label: title, current: true },
  ]" />

  <PageHeader :title="title" :subtitle="subtitle" />

  <div class="mb-4 flex gap-2">
    <Button v-if="archived && unarchiveUrl" type="button" size="sm" variant="outline" @click="router.post(unarchiveUrl)">
      取消归档
    </Button>
    <Button v-else-if="!archived && archiveUrl" type="button" size="sm" variant="outline" @click="router.post(archiveUrl)">
      归档会话
    </Button>
  </div>

  <div v-if="conversation.is_group && participants.length" class="mb-4">
    <p class="mb-2 text-xs font-semibold text-muted-foreground">群组成员</p>
    <div class="flex flex-wrap gap-2">
      <span v-for="p in participants" :key="p.username" class="inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs">
        <img :src="p.avatar_url" :alt="p.username" class="h-4 w-4 rounded-full" />
        {{ p.username }}
        <span v-if="p.is_creator" class="text-muted-foreground">（群主）</span>
        <button
          v-if="p.remove_url"
          type="button"
          class="ml-1 text-muted-foreground hover:text-destructive"
          :title="p.is_self ? '离开群组' : '移除成员'"
          @click="removeParticipant(p)"
        >
          {{ p.is_self ? '离开' : '×' }}
        </button>
      </span>
    </div>
    <form v-if="addParticipantUrl" class="mt-3 flex max-w-sm gap-2" @submit.prevent="addParticipant">
      <Input v-model="addUsername" placeholder="用户名" class="flex-1" />
      <Button type="submit" variant="outline" size="sm">添加成员</Button>
    </form>
  </div>

  <div class="mb-6 max-h-[50vh] space-y-3 overflow-y-auto rounded-lg border p-4">
    <div
      v-for="msg in messages"
      :key="msg.id"
      class="flex gap-2"
      :class="msg.is_mine ? 'flex-row-reverse' : ''"
    >
      <img :src="msg.avatar_url" :alt="msg.author" class="h-8 w-8 shrink-0 rounded-full" />
      <div
        class="max-w-[75%] rounded-lg px-3 py-2 text-sm"
        :class="msg.is_mine ? 'bg-primary text-primary-foreground' : 'bg-muted'"
      >
        <p v-if="conversation.is_group && !msg.is_mine" class="mb-1 text-xs font-medium opacity-80">{{ msg.author }}</p>
        <div class="prose prose-sm max-w-none dark:prose-invert" v-html="msg.body_html" />
        <p class="mt-1 text-[10px] opacity-70">
          {{ msg.created_at }}
          <span v-if="msg.is_mine && msg.read_by?.length" class="ml-1">已读：{{ msg.read_by.join('、') }}</span>
        </p>
      </div>
    </div>
  </div>

  <Pagination v-if="pagination.pages > 1" class="mb-4" :pagination="pagination" :base-path="`/app/forum/conversations/${conversation.id}`" />

  <form class="max-w-2xl space-y-3" @submit.prevent="submit">
    <MarkdownEditor v-model="form.message.body" :show-mention="false" :rows="3" placeholder="输入消息…" />
    <Button type="submit" :disabled="form.processing">发送</Button>
  </form>
</template>
