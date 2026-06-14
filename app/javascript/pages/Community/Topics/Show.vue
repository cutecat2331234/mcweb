<script setup lang="ts">
import { ref, watch, onMounted } from 'vue'
import { Head, Link, router, useForm, usePage } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import MarkdownEditor from '@/components/portal/MarkdownEditor.vue'
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
  signature_html?: string | null
  created_at: string
  edited_at: string | null
  edits_url: string | null
  quoted_post: QuotedPost | null
  reaction_counts: Record<string, number>
  reaction_users?: Record<string, string[]>
  reactions_total?: number
  user_reactions: string[]
  can_edit: boolean
  can_delete: boolean
  can_moderate: boolean
  hidden: boolean
  report_url: string | null
  bookmarked: boolean
  bookmark_url: string | null
  bookmark?: {
    id: number
    update_url: string
    note: string | null
    remind_at_input: string | null
  } | null
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
  multiple_choice?: boolean
  max_choices?: number
  hide_results_until_vote?: boolean
  show_results?: boolean
  options?: Array<{ label: string; index: number }>
  results: Array<{ label: string; index: number; votes: number }>
  total_votes: number | null
  user_vote_index: number | null
  user_vote_indices?: number[]
  vote_url: string
  close_url?: string | null
  closes_at?: string | null
}

const props = defineProps<{
  topic: {
    id: string
    title: string
    author: string | null
    locked: boolean
    pinned: boolean
    pinned_until?: string | null
    bumped_at?: string | null
    prefix?: string | null
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
    auto_close_at?: string | null
    solved_post_id: number | null
    tags: Array<{ name: string; slug: string; url: string }>
    tags_string: string
    section: { name: string; slug: string; url: string }
    section_prefixes?: string[]
  }
  posts: PostItem[]
  pagination: PaginationMeta
  lastReadFloor?: number
  firstUnreadFloor?: number | null
  markUnreadUrl?: string | null
  jumpToUnreadUrl?: string | null
  canReply: boolean
  canMarkSolved: boolean
  reactionEmojis: string[]
  sections: SectionOption[]
  reportTopicUrl: string | null
  poll: PollItem | null
  topicSearchQuery?: string
  topicBookmark?: {
    id: number
    update_url: string
    note: string | null
    remind_at_input: string | null
  } | null
  replyDraft?: string | null
  replyDraftUrl?: string | null
  meta?: { title: string; description: string | null }
}>()

const page = usePage<{ auth: { user: { id: string; username: string } | null } }>()
const loggedIn = !!page.props.auth.user

const editingPostId = ref<number | null>(null)
const editBody = ref('')
const editReason = ref('')
const editingTopic = ref(false)
const editTitle = ref(props.topic.title)
const editTags = ref(props.topic.tags_string)
const editPrefix = ref(props.topic.prefix || '')

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
const mergeTargetId = ref('')
const slowModeSeconds = ref(props.topic.slow_mode_seconds || 0)
const autoCloseAt = ref('')
const draftKey = `forum-reply-draft-${props.topic.id}`
const topicSearch = ref(props.topicSearchQuery || '')
const selectedPollOptions = ref<number[]>(props.poll?.user_vote_indices || [])
const editingBookmark = ref(false)
const bookmarkNote = ref(props.topicBookmark?.note || '')
const bookmarkRemindAt = ref(props.topicBookmark?.remind_at_input || '')
const editingPostBookmarkId = ref<number | null>(null)
const postBookmarkNote = ref('')
const postBookmarkRemindAt = ref('')
let draftSaveTimer: ReturnType<typeof setTimeout> | null = null

onMounted(() => {
  const saved = props.replyDraft || localStorage.getItem(draftKey)
  if (saved && !replyForm.post.body) {
    replyForm.post.body = saved
  }
  document.querySelectorAll('.code-copy-btn').forEach((button) => {
    button.addEventListener('click', () => {
      const wrap = button.closest('.code-block-wrap')
      const code = wrap?.querySelector('code')?.textContent
      if (code) navigator.clipboard.writeText(code)
    })
  })
  const hash = window.location.hash
  if (hash.startsWith('#post-')) {
    setTimeout(() => {
      document.querySelector(hash)?.scrollIntoView({ behavior: 'smooth', block: 'center' })
    }, 100)
  }
})

watch(() => replyForm.post.body, (body) => {
  if (body.trim()) {
    localStorage.setItem(draftKey, body)
    if (props.replyDraftUrl) {
      if (draftSaveTimer) clearTimeout(draftSaveTimer)
      draftSaveTimer = setTimeout(() => {
        fetch(props.replyDraftUrl!, {
          method: 'PATCH',
          headers: {
            'Content-Type': 'application/json',
            'X-CSRF-Token': document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content || '',
          },
          body: JSON.stringify({ body }),
          credentials: 'same-origin',
        }).catch(() => {})
      }, 800)
    }
  } else {
    localStorage.removeItem(draftKey)
    if (props.replyDraftUrl) {
      fetch(props.replyDraftUrl, {
        method: 'DELETE',
        headers: {
          'X-CSRF-Token': document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content || '',
        },
        credentials: 'same-origin',
      }).catch(() => {})
    }
  }
})

function submitReply() {
  replyForm.post('/forum/posts', {
    preserveScroll: true,
    onSuccess: () => {
      replyForm.post.body = ''
      replyForm.post.quoted_post_id = null
      replyForm.post.parent_post_id = null
      quotePreview.value = null
      replyPreview.value = null
      localStorage.removeItem(draftKey)
      if (props.replyDraftUrl) {
        fetch(props.replyDraftUrl, {
          method: 'DELETE',
          headers: {
            'X-CSRF-Token': document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content || '',
          },
          credentials: 'same-origin',
        }).catch(() => {})
      }
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

function updateAutoClose() {
  router.patch(`/forum/topics/${props.topic.id}/auto_close`, { auto_close_at: autoCloseAt.value || null })
}

function reactionTitle(post: PostItem, emoji: string) {
  const users = post.reaction_users?.[emoji]
  return users?.length ? users.join('、') : ''
}

function copyPermalink(post: PostItem) {
  const url = `${window.location.origin}${routes.forumTopic(props.topic.id)}#post-${post.id}`
  navigator.clipboard.writeText(url)
}

function markUnread() {
  if (!props.markUnreadUrl) return
  router.post(props.markUnreadUrl, {}, { preserveScroll: true })
}

function startEdit(post: PostItem) {
  editingPostId.value = post.id
  editBody.value = post.body
}

function cancelEdit() {
  editingPostId.value = null
  editBody.value = ''
  editReason.value = ''
}

function saveEdit(post: PostItem) {
  router.patch(post.update_url, { post: { body: editBody.value, reason: editReason.value } }, {
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
  if (props.topic.bookmarked && props.topicBookmark) {
    editingBookmark.value = !editingBookmark.value
    bookmarkNote.value = props.topicBookmark.note || ''
    bookmarkRemindAt.value = props.topicBookmark.remind_at_input || ''
    return
  }
  router.post(`/forum/topics/${props.topic.id}/bookmark`, {}, { preserveScroll: true })
}

function saveBookmark() {
  if (!props.topicBookmark) return
  router.patch(props.topicBookmark.update_url, {
    bookmark: {
      note: bookmarkNote.value,
      remind_at: bookmarkRemindAt.value || null,
    },
  }, {
    preserveScroll: true,
    onSuccess: () => { editingBookmark.value = false },
  })
}

function removeBookmark() {
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

function mergeTopic() {
  if (!mergeTargetId.value.trim()) return
  if (!confirm('确定将此主题合并到目标主题？源主题将被隐藏。')) return
  router.post(`/forum/topics/${props.topic.id}/merge`, { target_topic_id: mergeTargetId.value.trim() })
}

function saveTopicEdit() {
  router.patch(`/forum/topics/${props.topic.id}`, {
    topic: { title: editTitle.value, tags: editTags.value, prefix: editPrefix.value },
  }, {
    onSuccess: () => { editingTopic.value = false },
  })
}

function hasReacted(post: PostItem, emoji: string) {
  return post.user_reactions.includes(emoji)
}

function togglePostBookmark(post: PostItem) {
  if (!post.bookmark_url) return
  if (post.bookmarked && post.bookmark) {
    editingPostBookmarkId.value = post.id
    postBookmarkNote.value = post.bookmark.note || ''
    postBookmarkRemindAt.value = post.bookmark.remind_at_input || ''
    return
  }
  router.post(post.bookmark_url, {}, { preserveScroll: true })
}

function savePostBookmark(post: PostItem) {
  if (!post.bookmark?.update_url) return
  router.patch(post.bookmark.update_url, {
    bookmark: {
      note: postBookmarkNote.value,
      remind_at: postBookmarkRemindAt.value || null,
    },
  }, {
    preserveScroll: true,
    onSuccess: () => { editingPostBookmarkId.value = null },
  })
}

function removePostBookmark(post: PostItem) {
  if (!post.bookmark_url) return
  router.post(post.bookmark_url, {}, { preserveScroll: true })
}

function votePoll(optionIndex: number) {
  if (!props.poll) return
  if (props.poll.multiple_choice) return
  router.post(props.poll.vote_url, { option_index: optionIndex }, { preserveScroll: true })
}

function togglePollOption(index: number) {
  const max = props.poll?.max_choices || 1
  const current = [...selectedPollOptions.value]
  const pos = current.indexOf(index)
  if (pos >= 0) {
    current.splice(pos, 1)
  } else if (current.length < max) {
    current.push(index)
  }
  selectedPollOptions.value = current.sort((a, b) => a - b)
}

function submitMultiPoll() {
  if (!props.poll) return
  router.post(props.poll.vote_url, { option_indices: selectedPollOptions.value }, { preserveScroll: true })
}

function closePoll() {
  if (!props.poll?.close_url) return
  if (!confirm('确定关闭此投票？')) return
  router.post(props.poll.close_url, {}, { preserveScroll: true })
}

function searchInTopic() {
  router.get(routes.forumTopic(props.topic.id), { q: topicSearch.value || undefined }, { preserveScroll: true })
}

function pollVoted(index: number) {
  if (props.poll?.multiple_choice) {
    return (props.poll.user_vote_indices || []).includes(index)
  }
  return props.poll?.user_vote_index === index
}

function pollPercent(votes: number) {
  if (!props.poll || !props.poll.show_results || !props.poll.total_votes) return 0
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
      :title="`${topic.prefix ? `[${topic.prefix}] ` : ''}${topic.pinned ? '[置顶] ' : ''}${topic.title}`"
      :subtitle="`${topic.author ? `作者 ${topic.author}` : ''}${topic.author ? ' · ' : ''}${topic.views_count} 次浏览`"
    />
    <div class="flex flex-wrap gap-2">
      <Button v-if="topic.can_edit" type="button" variant="outline" size="sm" @click="editingTopic = !editingTopic">
        编辑主题
      </Button>
      <Button v-if="loggedIn" type="button" variant="outline" size="sm" @click="toggleBookmark">
        {{ topic.bookmarked ? '编辑书签' : '加入书签' }}
      </Button>
      <Button v-if="loggedIn && topic.bookmarked" type="button" variant="outline" size="sm" @click="removeBookmark">
        移除书签
      </Button>
      <Button v-if="loggedIn" type="button" variant="outline" size="sm" @click="toggleWatch">
        {{ topic.watching ? '取消关注' : '关注主题' }}
      </Button>
      <Button v-if="markUnreadUrl" type="button" variant="outline" size="sm" @click="markUnread">标为未读</Button>
      <Button v-if="jumpToUnreadUrl" as-child variant="outline" size="sm">
        <Link :href="jumpToUnreadUrl">跳到未读</Link>
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
        <Button v-if="topic.can_moderate && !topic.pinned" type="button" variant="outline" size="sm" @click="moderate('pin_7')">
          置顶 7 天
        </Button>
        <Button type="button" variant="outline" size="sm" @click="moderate('bump')">提升主题</Button>
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
    <div v-if="topic.section_prefixes?.length" class="space-y-1">
      <label class="text-sm">前缀</label>
      <select v-model="editPrefix" class="h-9 w-full rounded-md border px-2 text-sm">
        <option value="">无前缀</option>
        <option v-for="p in topic.section_prefixes" :key="p" :value="p">{{ p }}</option>
      </select>
    </div>
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

  <div v-if="editingBookmark && topicBookmark" class="mb-4 max-w-xl space-y-2 rounded-lg border p-4">
    <p class="text-sm font-medium">书签备注与提醒</p>
    <textarea v-model="bookmarkNote" rows="2" class="w-full rounded-md border px-2 py-1 text-sm" placeholder="备注" />
    <input v-model="bookmarkRemindAt" type="datetime-local" class="h-9 w-full rounded-md border px-2 text-sm" />
    <div class="flex gap-2">
      <Button type="button" size="sm" @click="saveBookmark">保存</Button>
      <Button type="button" size="sm" variant="outline" @click="editingBookmark = false">取消</Button>
    </div>
  </div>

  <section v-if="poll" class="mb-6 max-w-xl rounded-lg border p-4">
    <div class="mb-3 flex items-center justify-between gap-2">
      <h2 class="text-sm font-semibold">{{ poll.question }}</h2>
      <Button v-if="poll.close_url" type="button" variant="outline" size="sm" @click="closePoll">关闭投票</Button>
    </div>
    <p v-if="poll.multiple_choice" class="mb-2 text-xs text-muted-foreground">多选（最多 {{ poll.max_choices }} 项）</p>
    <p v-if="poll.closes_at && poll.open" class="mb-2 text-xs text-muted-foreground">投票将于 {{ poll.closes_at }} 结束</p>
    <p v-if="!poll.open" class="mb-3 text-xs text-muted-foreground">投票已结束</p>
    <p v-if="poll.hide_results_until_vote && !poll.show_results" class="mb-3 text-xs text-muted-foreground">
      投票后可查看结果
    </p>
    <div v-if="poll.show_results" class="space-y-2">
      <div v-for="option in poll.results" :key="option.index" class="space-y-1">
        <div class="flex items-center justify-between gap-2 text-sm">
          <span>{{ option.label }}</span>
          <span class="text-muted-foreground">{{ option.votes }} 票 ({{ pollPercent(option.votes) }}%)</span>
        </div>
        <div class="h-2 overflow-hidden rounded-full bg-muted">
          <div class="h-full bg-primary transition-all" :style="{ width: `${pollPercent(option.votes)}%` }" />
        </div>
        <Button
          v-if="poll.open && loggedIn && !poll.multiple_choice && !pollVoted(option.index)"
          type="button"
          size="sm"
          variant="outline"
          @click="votePoll(option.index)"
        >
          {{ poll.user_vote_index === null ? '投票' : '改投此项' }}
        </Button>
        <span v-else-if="pollVoted(option.index)" class="text-xs text-primary">你已投票</span>
      </div>
    </div>
    <div v-else-if="poll.open && loggedIn && poll.options?.length" class="space-y-2">
      <template v-if="poll.multiple_choice">
        <label v-for="option in poll.options" :key="option.index" class="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            :checked="selectedPollOptions.includes(option.index)"
            @change="togglePollOption(option.index)"
          />
          {{ option.label }}
        </label>
        <Button type="button" size="sm" :disabled="!selectedPollOptions.length" @click="submitMultiPoll">提交投票</Button>
      </template>
      <template v-else>
        <div v-for="option in poll.options" :key="option.index">
          <Button
            v-if="!pollVoted(option.index)"
            type="button"
            size="sm"
            variant="outline"
            @click="votePoll(option.index)"
          >
            {{ poll.user_vote_index === null ? '投票' : '改投此项' }}：{{ option.label }}
          </Button>
          <span v-else class="text-xs text-primary">已选：{{ option.label }}</span>
        </div>
      </template>
    </div>
    <p v-if="poll.show_results && poll.total_votes !== null" class="mt-3 text-xs text-muted-foreground">共 {{ poll.total_votes }} 票</p>
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
    <template v-if="topic.can_move">
      <Input v-model="mergeTargetId" placeholder="合并到主题 ID" class="h-8 w-40" />
      <Button type="button" size="sm" variant="outline" :disabled="!mergeTargetId" @click="mergeTopic">合并</Button>
    </template>
    <template v-if="topic.can_moderate">
      <Input v-model.number="slowModeSeconds" type="number" min="0" class="h-8 w-24" placeholder="慢速秒" />
      <Button type="button" size="sm" variant="outline" @click="updateSlowMode">设置慢速</Button>
      <Input v-model="autoCloseAt" type="datetime-local" class="h-8 w-48" />
      <Button type="button" size="sm" variant="outline" @click="updateAutoClose">定时关闭</Button>
    </template>
  </div>

  <p v-if="topic.pinned_until" class="mb-4 rounded-md border border-blue-200 bg-blue-50 px-4 py-3 text-sm text-blue-900">
    置顶将于 {{ topic.pinned_until }} 自动取消。
  </p>
  <p v-if="topic.bumped_at" class="mb-4 rounded-md border border-indigo-200 bg-indigo-50 px-4 py-3 text-sm text-indigo-900">
    最近提升：{{ topic.bumped_at }}
  </p>
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
  <p v-if="topic.auto_close_at" class="mb-4 rounded-md border border-orange-200 bg-orange-50 px-4 py-3 text-sm text-orange-900">
    将于 {{ topic.auto_close_at }} 自动关闭。
  </p>
  <p v-if="topic.locked" class="mb-4 rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900 dark:border-amber-900 dark:bg-amber-950 dark:text-amber-100">
    此主题已锁定，无法回复。
  </p>

  <form class="mb-4 flex max-w-md gap-2" @submit.prevent="searchInTopic">
    <Input v-model="topicSearch" placeholder="在此主题内搜索帖子…" class="flex-1" />
    <Button type="submit" variant="outline">搜索</Button>
  </form>

  <div class="space-y-4">
    <template v-for="post in posts" :key="post.id">
      <div
        v-if="lastReadFloor && post.floor_number === lastReadFloor + 1"
        class="flex items-center gap-3 text-xs text-primary"
      >
        <span class="h-px flex-1 bg-primary/30" />
        <span>上次读到这里</span>
        <span class="h-px flex-1 bg-primary/30" />
      </div>
      <article
        :id="`post-${post.id}`"
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
              <button type="button" class="text-xs hover:underline" @click="copyPermalink(post)">复制链接</button>
              <button v-if="canReply" type="button" class="text-xs hover:underline" @click="replyToPost(post)">回复</button>
              <button v-if="post.bookmark_url" type="button" class="text-xs hover:underline" @click="togglePostBookmark(post)">
                {{ post.bookmarked ? '编辑书签' : '书签' }}
              </button>
              <button v-if="post.bookmarked && post.bookmark_url" type="button" class="text-xs hover:underline" @click="removePostBookmark(post)">移除书签</button>
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
            <a :href="`#post-${post.quoted_post.id}`" class="hover:underline">
              <span class="font-medium">#{{ post.quoted_post.floor_number }} {{ post.quoted_post.author }}：</span>
              {{ post.quoted_post.excerpt }}
            </a>
          </blockquote>

          <div v-if="editingPostBookmarkId === post.id && post.bookmark" class="mt-2 space-y-2 rounded border bg-muted/30 p-3">
            <textarea v-model="postBookmarkNote" rows="2" class="w-full rounded-md border px-2 py-1 text-sm" placeholder="书签备注" />
            <input v-model="postBookmarkRemindAt" type="datetime-local" class="h-8 w-full rounded-md border px-2 text-sm" />
            <div class="flex gap-2">
              <Button type="button" size="sm" @click="savePostBookmark(post)">保存</Button>
              <Button type="button" size="sm" variant="outline" @click="editingPostBookmarkId = null">取消</Button>
            </div>
          </div>

          <div v-if="editingPostId === post.id" class="mt-2 space-y-2">
            <MarkdownEditor v-model="editBody" :rows="6" />
            <Input v-model="editReason" placeholder="编辑说明（可选）" class="h-8" />
            <div class="flex gap-2">
              <Button type="button" size="sm" @click="saveEdit(post)">保存</Button>
              <Button type="button" size="sm" variant="outline" @click="cancelEdit">取消</Button>
            </div>
          </div>
          <div v-else class="prose prose-sm mt-2 max-w-none text-sm dark:prose-invert" v-html="post.body_html" />
          <div v-if="post.signature_html" class="mt-3 border-t pt-2 text-xs text-muted-foreground prose prose-sm max-w-none" v-html="post.signature_html" />

          <div class="mt-3 flex flex-wrap items-center gap-2">
            <span v-if="post.reactions_total" class="text-xs text-muted-foreground">{{ post.reactions_total }} 个反应</span>
            <template v-if="loggedIn">
              <button
                v-for="emoji in reactionEmojis"
                :key="emoji"
                type="button"
                class="rounded-full border px-2 py-0.5 text-xs transition-colors"
                :class="hasReacted(post, emoji) ? 'border-primary bg-primary/10' : 'hover:bg-muted'"
                :title="reactionTitle(post, emoji)"
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
    </template>
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
      <MarkdownEditor v-model="replyForm.post.body" :rows="6" placeholder="写下你的回复… 输入 @ 可提及用户" required />
      <Button type="submit" :disabled="replyForm.processing">发表回复</Button>
    </form>
  </section>
</template>
