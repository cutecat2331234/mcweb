<script setup lang="ts">
import { ref } from 'vue'
import { Head, Link, router, useForm, usePage } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
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
  parent_post_id: number | null
  depth: number
  is_solved: boolean
  author: string
  author_url: string
  avatar_url: string
  body: string
  body_html: string
  created_at: string
  edited_at: string | null
  edits_url: string | null
  quoted_post: QuotedPost | null
  reaction_counts: Record<string, number>
  user_reactions: string[]
  can_edit: boolean
  can_delete: boolean
  can_moderate: boolean
  hidden: boolean
  report_url: string | null
  bookmarked: boolean
  bookmark_url: string | null
  update_url: string
}

export interface SectionOption {
  slug: string
  name: string
  category: string | null
}

export interface PollItem {
  id: number
  question: string
  open: boolean
  results: Array<{ label: string; index: number; votes: number }>
  total_votes: number
  user_vote_index: number | null
  vote_url: string
}

const props = defineProps<{
  topic: {
    id: string
    title: string
    author: string | null
    locked: boolean
    pinned: boolean
    hidden: boolean
    views_count: number
    watching: boolean
    bookmarked: boolean
    can_moderate: boolean
    can_move: boolean
    can_edit: boolean
    featured: boolean
    wiki: boolean
    slow_mode_seconds: number | null
    solved_post_id: number | null
    tags: Array<{ name: string; slug: string; url: string }>
    tags_string: string
    section: { name: string; slug: string; url: string }
  }
  posts: PostItem[]
  pagination: PaginationMeta
  canReply: boolean
  canMarkSolved: boolean
  reactionEmojis: string[]
  sections: SectionOption[]
  reportTopicUrl: string | null
  poll: PollItem | null
  meta?: { title: string; description: string | null }
}>()

const page = usePage<{ auth: { user: { id: string; username: string } | null } }>()
const loggedIn = !!page.props.auth.user

const editingPostId = ref<number | null>(null)
const editBody = ref('')
const editingTopic = ref(false)
const editTitle = ref(props.topic.title)
const editTags = ref(props.topic.tags_string)

const replyForm = useForm({
  post: {
    topic_id: props.topic.id,
    body: '',
    quoted_post_id: null as number | null,
    parent_post_id: null as number | null,
  },
})

const quotePreview = ref<QuotedPost | null>(null)
const replyPreview = ref<{ id: number; floor_number: number; author: string } | null>(null)
const moveSectionSlug = ref('')
const slowModeSeconds = ref(props.topic.slow_mode_seconds || 0)

function submitReply() {
  replyForm.post('/forum/posts', {
    preserveScroll: true,
    onSuccess: () => {
      replyForm.post.body = ''
      replyForm.post.quoted_post_id = null
      replyForm.post.parent_post_id = null
      quotePreview.value = null
      replyPreview.value = null
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

function replyToPost(post: PostItem) {
  replyForm.post.parent_post_id = post.id
  replyForm.post.quoted_post_id = null
  quotePreview.value = null
  replyPreview.value = { id: post.id, floor_number: post.floor_number, author: post.author }
  document.getElementById('reply-form')?.scrollIntoView({ behavior: 'smooth' })
}

function clearReplyTarget() {
  replyForm.post.parent_post_id = null
  replyPreview.value = null
}

function markSolved(post: PostItem) {
  router.post(`/forum/topics/${props.topic.id}/mark_solved`, { post_id: post.id }, { preserveScroll: true })
}

function unsolveTopic() {
  router.post(`/forum/topics/${props.topic.id}/unsolve`, {}, { preserveScroll: true })
}

function updateSlowMode() {
  router.patch(`/forum/topics/${props.topic.id}/slow_mode`, { seconds: slowModeSeconds.value })
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

function toggleBookmark() {
  router.post(`/forum/topics/${props.topic.id}/bookmark`, {}, { preserveScroll: true })
}

function moderate(action: string) {
  router.post(`/forum/topics/${props.topic.id}/moderate`, { action_type: action }, { preserveScroll: true })
}

function moderatePost(post: PostItem, action: string) {
  router.post(`/forum/posts/${post.id}/moderate`, { action_type: action }, { preserveScroll: true })
}

function moveTopic() {
  if (!moveSectionSlug.value) return
  router.post(`/forum/topics/${props.topic.id}/move`, { section_slug: moveSectionSlug.value })
}

function saveTopicEdit() {
  router.patch(`/forum/topics/${props.topic.id}`, {
    topic: { title: editTitle.value, tags: editTags.value },
  }, {
    onSuccess: () => { editingTopic.value = false },
  })
}

function hasReacted(post: PostItem, emoji: string) {
  return post.user_reactions.includes(emoji)
}

function togglePostBookmark(post: PostItem) {
  if (!post.bookmark_url) return
  router.post(post.bookmark_url, {}, { preserveScroll: true })
}

function votePoll(optionIndex: number) {
  if (!props.poll) return
  router.post(props.poll.vote_url, { option_index: optionIndex }, { preserveScroll: true })
}

function pollPercent(votes: number) {
  if (!props.poll || props.poll.total_votes === 0) return 0
  return Math.round((votes / props.poll.total_votes) * 100)
}
</script>

<template>
  <Head v-if="meta">
    <title>{{ meta.title }}</title>
    <meta v-if="meta.description" head-key="description" name="description" :content="meta.description" />
    <meta head-key="og:title" property="og:title" :content="meta.title" />
    <meta v-if="meta.description" head-key="og:description" property="og:description" :content="meta.description" />
    <meta head-key="og:type" property="og:type" content="article" />
  </Head>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: topic.section.name, href: topic.section.url },
    { label: topic.title, current: true },
  ]" />

  <div class="mb-4 flex flex-wrap items-start justify-between gap-3">
    <PageHeader
      :title="`${topic.pinned ? '[置顶] ' : ''}${topic.title}`"
      :subtitle="`${topic.author ? `作者 ${topic.author}` : ''}${topic.author ? ' · ' : ''}${topic.views_count} 次浏览`"
    />
    <div class="flex flex-wrap gap-2">
      <Button v-if="topic.can_edit" type="button" variant="outline" size="sm" @click="editingTopic = !editingTopic">
        编辑主题
      </Button>
      <Button v-if="loggedIn" type="button" variant="outline" size="sm" @click="toggleBookmark">
        {{ topic.bookmarked ? '移除书签' : '加入书签' }}
      </Button>
      <Button v-if="loggedIn" type="button" variant="outline" size="sm" @click="toggleWatch">
        {{ topic.watching ? '取消关注' : '关注主题' }}
      </Button>
      <Button v-if="reportTopicUrl" as-child variant="outline" size="sm">
        <Link :href="reportTopicUrl">举报主题</Link>
      </Button>
      <template v-if="topic.can_moderate">
        <Button type="button" variant="outline" size="sm" @click="moderate(topic.locked ? 'unlock' : 'lock')">
          {{ topic.locked ? '解锁' : '锁定' }}
        </Button>
        <Button type="button" variant="outline" size="sm" @click="moderate(topic.pinned ? 'unpin' : 'pin')">
          {{ topic.pinned ? '取消置顶' : '置顶' }}
        </Button>
        <Button type="button" variant="outline" size="sm" @click="moderate(topic.featured ? 'unfeature' : 'feature')">
          {{ topic.featured ? '取消精选' : '设为精选' }}
        </Button>
        <Button type="button" variant="outline" size="sm" @click="moderate(topic.hidden ? 'unhide' : 'hide')">
          {{ topic.hidden ? '取消隐藏' : '隐藏主题' }}
        </Button>
        <Button type="button" variant="outline" size="sm" @click="moderate(topic.wiki ? 'disable_wiki' : 'enable_wiki')">
          {{ topic.wiki ? '关闭 Wiki' : '开启 Wiki' }}
        </Button>
      </template>
    </div>
  </div>

  <div v-if="editingTopic" class="mb-4 max-w-xl space-y-3 rounded-lg border p-4">
    <Input v-model="editTitle" placeholder="主题标题" />
    <Input v-model="editTags" placeholder="标签（逗号分隔，最多5个）" />
    <div class="flex gap-2">
      <Button type="button" size="sm" @click="saveTopicEdit">保存</Button>
      <Button type="button" size="sm" variant="outline" @click="editingTopic = false">取消</Button>
    </div>
  </div>

  <div v-if="topic.tags.length" class="mb-4 flex flex-wrap gap-2">
    <Link
      v-for="tag in topic.tags"
      :key="tag.slug"
      :href="tag.url"
      class="rounded-full border px-2 py-0.5 text-xs hover:bg-muted"
    >
      #{{ tag.name }}
    </Link>
  </div>

  <section v-if="poll" class="mb-6 max-w-xl rounded-lg border p-4">
    <h2 class="mb-3 text-sm font-semibold">{{ poll.question }}</h2>
    <p v-if="!poll.open" class="mb-3 text-xs text-muted-foreground">投票已结束</p>
    <div class="space-y-2">
      <div v-for="option in poll.results" :key="option.index" class="space-y-1">
        <div class="flex items-center justify-between gap-2 text-sm">
          <span>{{ option.label }}</span>
          <span class="text-muted-foreground">{{ option.votes }} 票 ({{ pollPercent(option.votes) }}%)</span>
        </div>
        <div class="h-2 overflow-hidden rounded-full bg-muted">
          <div class="h-full bg-primary transition-all" :style="{ width: `${pollPercent(option.votes)}%` }" />
        </div>
        <Button
          v-if="poll.open && loggedIn && poll.user_vote_index !== option.index"
          type="button"
          size="sm"
          variant="outline"
          @click="votePoll(option.index)"
        >
          {{ poll.user_vote_index === null ? '投票' : '改投此项' }}
        </Button>
        <span v-else-if="poll.user_vote_index === option.index" class="text-xs text-primary">你已投票</span>
      </div>
    </div>
    <p class="mt-3 text-xs text-muted-foreground">共 {{ poll.total_votes }} 票</p>
  </section>

  <div v-if="topic.can_move && sections.length" class="mb-4 flex flex-wrap items-center gap-2">
    <label class="text-sm text-muted-foreground">移动到分区：</label>
    <select v-model="moveSectionSlug" class="h-8 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="">选择分区…</option>
      <option v-for="section in sections" :key="section.slug" :value="section.slug">
        {{ section.category ? `${section.category} / ` : '' }}{{ section.name }}
      </option>
    </select>
    <Button type="button" size="sm" variant="outline" :disabled="!moveSectionSlug" @click="moveTopic">移动</Button>
    <template v-if="topic.can_moderate">
      <Input v-model.number="slowModeSeconds" type="number" min="0" class="h-8 w-24" placeholder="慢速秒" />
      <Button type="button" size="sm" variant="outline" @click="updateSlowMode">设置慢速</Button>
    </template>
  </div>

  <p v-if="topic.hidden" class="mb-4 rounded-md border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-900 dark:border-red-900 dark:bg-red-950 dark:text-red-100">
    此主题已被版主隐藏。
  </p>
  <p v-if="topic.wiki" class="mb-4 rounded-md border border-blue-200 bg-blue-50 px-4 py-3 text-sm text-blue-900">
    Wiki 主题：所有登录用户可协作编辑帖子。
  </p>
  <p v-if="topic.solved_post_id" class="mb-4 rounded-md border border-green-200 bg-green-50 px-4 py-3 text-sm text-green-900">
    此主题已标记为已解决。
    <button v-if="canMarkSolved" type="button" class="ml-2 underline" @click="unsolveTopic">取消已解决</button>
  </p>
  <p v-if="topic.slow_mode_seconds" class="mb-4 rounded-md border border-purple-200 bg-purple-50 px-4 py-3 text-sm text-purple-900">
    慢速模式：同一用户需间隔 {{ topic.slow_mode_seconds }} 秒才能再次回复。
  </p>
  <p v-if="topic.locked" class="mb-4 rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900 dark:border-amber-900 dark:bg-amber-950 dark:text-amber-100">
    此主题已锁定，无法回复。
  </p>

  <div class="space-y-4">
    <article
      v-for="post in posts"
      :id="`post-${post.id}`"
      :key="post.id"
      class="rounded-lg border p-4"
      :class="[post.hidden ? 'opacity-60 border-dashed' : '', post.is_solved ? 'border-green-400 bg-green-50/50 dark:bg-green-950/20' : '']"
      :style="{ marginLeft: `${post.depth * 1.5}rem` }"
    >
      <div class="mb-3 flex items-start gap-3">
        <img :src="post.avatar_url" :alt="post.author" class="h-9 w-9 shrink-0 rounded-full" />
        <div class="min-w-0 flex-1">
          <div class="flex items-center justify-between gap-2 text-sm text-muted-foreground">
            <div>
              <span class="font-medium text-foreground">#{{ post.floor_number }}</span>
              <span v-if="post.is_solved" class="ml-2 text-xs text-green-600">[已解决]</span>
              <span class="mx-2">·</span>
              <Link :href="post.author_url" class="font-medium text-foreground hover:underline">{{ post.author }}</Link>
              <span class="mx-2">·</span>
              <span>{{ post.created_at }}</span>
              <span v-if="post.edited_at" class="ml-2">
                （已编辑 {{ post.edited_at }}
                <Link v-if="post.edits_url" :href="post.edits_url" class="hover:underline">历史</Link>）
              </span>
              <span v-if="post.hidden" class="ml-2 text-amber-600">[已隐藏]</span>
            </div>
            <div class="flex gap-2">
              <button v-if="canReply" type="button" class="text-xs hover:underline" @click="quotePost(post)">引用</button>
              <button v-if="canReply" type="button" class="text-xs hover:underline" @click="replyToPost(post)">回复</button>
              <button v-if="post.bookmark_url" type="button" class="text-xs hover:underline" @click="togglePostBookmark(post)">
                {{ post.bookmarked ? '移除书签' : '书签' }}
              </button>
              <button v-if="canMarkSolved && !post.is_solved" type="button" class="text-xs text-green-600 hover:underline" @click="markSolved(post)">标为已解决</button>
              <Link v-if="post.report_url" :href="post.report_url" class="text-xs hover:underline">举报</Link>
              <button v-if="post.can_moderate" type="button" class="text-xs hover:underline" @click="moderatePost(post, post.hidden ? 'unhide' : 'hide')">
                {{ post.hidden ? '显示' : '隐藏' }}
              </button>
              <button v-if="post.can_edit && editingPostId !== post.id" type="button" class="text-xs hover:underline" @click="startEdit(post)">编辑</button>
              <button v-if="post.can_delete" type="button" class="text-xs text-destructive hover:underline" @click="deletePost(post)">删除</button>
            </div>
          </div>

          <blockquote v-if="post.quoted_post" class="mb-3 mt-2 border-l-2 border-muted pl-3 text-sm text-muted-foreground">
            <span class="font-medium">#{{ post.quoted_post.floor_number }} {{ post.quoted_post.author }}：</span>
            {{ post.quoted_post.excerpt }}
          </blockquote>

          <div v-if="editingPostId === post.id" class="mt-2 space-y-2">
            <Textarea v-model="editBody" rows="6" />
            <div class="flex gap-2">
              <Button type="button" size="sm" @click="saveEdit(post)">保存</Button>
              <Button type="button" size="sm" variant="outline" @click="cancelEdit">取消</Button>
            </div>
          </div>
          <div v-else class="prose prose-sm mt-2 max-w-none text-sm dark:prose-invert" v-html="post.body_html" />

          <div class="mt-3 flex flex-wrap gap-1">
            <template v-if="loggedIn">
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
            </template>
            <template v-else>
              <span
                v-for="emoji in reactionEmojis"
                :key="emoji"
                v-show="post.reaction_counts[emoji]"
                class="rounded-full border px-2 py-0.5 text-xs text-muted-foreground"
              >
                {{ emoji }} {{ post.reaction_counts[emoji] }}
              </span>
            </template>
          </div>
        </div>
      </div>
    </article>
  </div>

  <Pagination :pagination="pagination" :base-path="routes.forumTopic(topic.id)" />

  <section v-if="canReply" id="reply-form" class="mt-8 max-w-2xl">
    <h2 class="mb-3 text-sm font-semibold">回复</h2>
    <div v-if="replyPreview" class="mb-3 rounded-md border bg-muted/40 p-3 text-sm">
      <div class="flex items-start justify-between gap-2">
        <p>回复 #{{ replyPreview.floor_number }} {{ replyPreview.author }}</p>
        <button type="button" class="text-xs text-muted-foreground hover:underline" @click="clearReplyTarget">清除</button>
      </div>
    </div>
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
