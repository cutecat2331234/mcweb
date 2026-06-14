<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Textarea from '@/components/ui/Textarea.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  conversation: {
    id: number
    other_user: { username: string; avatar_url: string; profile_url: string }
  }
  messages: Array<{
    id: number
    body: string
    author: string
    avatar_url: string
    is_mine: boolean
    created_at: string
  }>
  pagination: PaginationMeta
}>()

const form = useForm({
  message: { body: '' },
})

function submit() {
  form.post(`/forum/conversations/${props.conversation.id}/messages`, {
    preserveScroll: true,
    onSuccess: () => { form.message.body = '' },
  })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '私信', href: routes.forumMessages },
    { label: conversation.other_user.username, current: true },
  ]" />

  <PageHeader :title="conversation.other_user.username" subtitle="私信对话" />

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
        <p class="whitespace-pre-wrap">{{ msg.body }}</p>
        <p class="mt-1 text-[10px] opacity-70">{{ msg.created_at }}</p>
      </div>
    </div>
  </div>

  <form class="max-w-2xl space-y-3" @submit.prevent="submit">
    <Textarea v-model="form.message.body" required rows="3" placeholder="输入消息…" />
    <Button type="submit" :disabled="form.processing">发送</Button>
  </form>
</template>
