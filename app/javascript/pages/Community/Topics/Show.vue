<script setup lang="ts">
import { ref } from 'vue'
import { Link, router, useForm, usePage } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import Button from '@/components/ui/Button.vue'
import Textarea from '@/components/ui/Textarea.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

export interface QuotedPost {
  id: number
  floor_number: number
  author: string
  excerpt: string
}

export interface PostItem {
  id: number
  floor_number: number
  author: string
  author_id: number
  body: string
  created_at: string
  edited_at: string | null
  quoted_post: QuotedPost | null
  reaction_counts: Record<string, number>
  user_reactions: string[]
  can_edit: boolean
  can_delete: boolean
  update_url: string
}

const props = defineProps<{
  topic: {
    id: string
    title: string
    author: string | null
    locked: boolean
    pinned: boolean
    watching: boolean
    can_moderate: boolean
    section: { name: string; slug: string; url: string }
  }
  posts: PostItem[]
  pagination: PaginationMeta
  canReply: boolean
  reactionEmojis: string[]
}>()

const page = usePage<{ auth: { user: { id: string; username: string } | null } }>()
const loggedIn = !!page.props.auth.user

const editingPostId = ref<number | null>(null)
const editBody = ref('')

const replyForm = useForm({
  post: {
    topic_id: props.topic.id,
    body: '',
    quoted_post_id: null as number | null,
  },
})

const quotePreview = ref<QuotedPost | null>(null)

function submitReply() {
  replyForm.post('/forum/posts', {
    preserveScroll: true,
    onSuccess: () => {
      replyForm.post.body = ''
      replyForm.post.quoted_post_id = null
      quotePreview.value = null
    },
  })
}

function quotePost(post: PostItem) {
  replyForm.post.quoted_post_id = post.id
  quotePreview.value = {
    id: post.id,
    floor_number: post.floor_number,
    author: post.author,
    excerpt: post.body.slice(0, 120),
  }
  document.getElementById('reply-form')?.scrollIntoView({ behavior: 'smooth' })
}

function clearQuote() {
  replyForm.post.quoted_post_id = null
  quotePreview.value = null
}

function startEdit(post: PostItem) {
  editingPostId.value = post.id
  editBody.value = post.body
}

function cancelEdit() {
  editingPostId.value = null
  editBody.value = ''
}

function saveEdit(post: PostItem) {
  router.patch(post.update_url, { post: { body: editBody.value } }, {
    preserveScroll: true,
    onSuccess: () => cancelEdit(),
  })
}

function deletePost(post: PostItem) {
  if (!confirm('确定删除此帖子？')) return
  router.delete(post.update_url, { preserveScroll: true })
}

function toggleReaction(post: PostItem, emoji: string) {
  router.post(`/forum/posts/${post.id}/reaction`, { emoji }, { preserveScroll: true })
}

function toggleWatch() {
  router.post(`/forum/topics/${props.topic.id}/subscription`, {}, { preserveScroll: true })
}

function moderate(action: string) {
  router.post(`/forum/topics/${props.topic.id}/moderate`, { action_type: action }, { preserveScroll: true })
}

function hasReacted(post: PostItem, emoji: string) {
  return post.user_reactions.includes(emoji)
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: topic.section.name, href: topic.section.url },
    { label: topic.title, current: true },
  ]" />

  <div class="mb-4 flex flex-wrap items-start justify-between gap-3">
    <PageHeader
      :title="`${topic.pinned ? '[置顶] ' : ''}${topic.title}`"
      :subtitle="topic.author ? `作者 ${topic.author}` : undefined"
    />
    <div class="flex flex-wrap gap-2">
      <Button v-if="loggedIn" type="button" variant="outline" size="sm" @click="toggleWatch">
        {{ topic.watching ? '取消关注' : '关注主题' }}
      </Button>
      <template v-if="topic.can_moderate">
        <Button type="button" variant="outline" size="sm" @click="moderate(topic.locked ? 'unlock' : 'lock')">
          {{ topic.locked ? '解锁' : '锁定' }}
        </Button>
        <Button type="button" variant="outline" size="sm" @click="moderate(topic.pinned ? 'unpin' : 'pin')">
          {{ topic.pinned ? '取消置顶' : '置顶' }}
        </Button>
      </template>
    </div>
  </div>

  <p v-if="topic.locked" class="mb-4 rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900 dark:border-amber-900 dark:bg-amber-950 dark:text-amber-100">
    此主题已锁定，无法回复。
  </p>

  <div class="space-y-4">
    <article
      v-for="post in posts"
      :id="`post-${post.id}`"
      :key="post.id"
      class="rounded-lg border p-4"
    >
      <div class="mb-3 flex items-center justify-between gap-2 text-sm text-muted-foreground">
        <div>
          <span class="font-medium text-foreground">#{{ post.floor_number }}</span>
          <span class="mx-2">·</span>
          <span>{{ post.author }}</span>
          <span class="mx-2">·</span>
          <span>{{ post.created_at }}</span>
          <span v-if="post.edited_at" class="ml-2">（已编辑 {{ post.edited_at }}）</span>
        </div>
        <div class="flex gap-2">
          <button v-if="canReply" type="button" class="text-xs hover:underline" @click="quotePost(post)">引用</button>
          <button v-if="post.can_edit && editingPostId !== post.id" type="button" class="text-xs hover:underline" @click="startEdit(post)">编辑</button>
          <button v-if="post.can_delete" type="button" class="text-xs text-destructive hover:underline" @click="deletePost(post)">删除</button>
        </div>
      </div>

      <blockquote v-if="post.quoted_post" class="mb-3 border-l-2 border-muted pl-3 text-sm text-muted-foreground">
        <span class="font-medium">#{{ post.quoted_post.floor_number }} {{ post.quoted_post.author }}：</span>
        {{ post.quoted_post.excerpt }}
      </blockquote>

      <div v-if="editingPostId === post.id" class="space-y-2">
        <Textarea v-model="editBody" rows="6" />
        <div class="flex gap-2">
          <Button type="button" size="sm" @click="saveEdit(post)">保存</Button>
          <Button type="button" size="sm" variant="outline" @click="cancelEdit">取消</Button>
        </div>
      </div>
      <p v-else class="whitespace-pre-wrap text-sm">{{ post.body }}</p>

      <div v-if="loggedIn" class="mt-3 flex flex-wrap gap-1">
        <button
          v-for="emoji in reactionEmojis"
          :key="emoji"
          type="button"
          class="rounded-full border px-2 py-0.5 text-xs transition-colors"
          :class="hasReacted(post, emoji) ? 'border-primary bg-primary/10' : 'hover:bg-muted'"
          @click="toggleReaction(post, emoji)"
        >
          {{ emoji }}
          <span v-if="post.reaction_counts[emoji]">{{ post.reaction_counts[emoji] }}</span>
        </button>
      </div>
    </article>
  </div>

  <Pagination :pagination="pagination" :base-path="routes.forumTopic(topic.id)" />

  <section v-if="canReply" id="reply-form" class="mt-8 max-w-2xl">
    <h2 class="mb-3 text-sm font-semibold">回复</h2>
    <div v-if="quotePreview" class="mb-3 rounded-md border bg-muted/40 p-3 text-sm">
      <div class="flex items-start justify-between gap-2">
        <p>
          引用 #{{ quotePreview.floor_number }} {{ quotePreview.author }}：
          {{ quotePreview.excerpt }}
        </p>
        <button type="button" class="text-xs text-muted-foreground hover:underline" @click="clearQuote">清除</button>
      </div>
    </div>
    <form class="space-y-3" @submit.prevent="submitReply">
      <Textarea v-model="replyForm.post.body" required rows="6" placeholder="写下你的回复…" />
      <Button type="submit" :disabled="replyForm.processing">发表回复</Button>
    </form>
  </section>
</template>
