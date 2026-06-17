<script setup lang="ts">
import { ref, watch, onMounted, onUnmounted, computed } from 'vue'
import { Head, Link, router, useForm, usePage } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Textarea from '@/components/ui/Textarea.vue'
import MarkdownEditor from '@/components/portal/MarkdownEditor.vue'
import TagGroupPicker from '@/components/portal/TagGroupPicker.vue'
import ReactionUsersPopover from '@/components/portal/ReactionUsersPopover.vue'
import UserHoverCard from '@/components/portal/UserHoverCard.vue'
import ReadingProgress from '@/components/portal/ReadingProgress.vue'
import ImageLightbox from '@/components/portal/ImageLightbox.vue'
import SubscriptionLevelSelect, { type SubscriptionLevelOption } from '@/components/portal/SubscriptionLevelSelect.vue'
import { routes } from '@/lib/routes'
import { highlightCodeBlocks } from '@/lib/highlightCode'

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
  author_username: string
  author_flair_color?: string | null
  author_forum_title?: string | null
  author_card_url?: string
  author_badges?: Array<{ name: string; icon: string | null; color: string | null; granted_at?: string }>
  verified_purchaser?: boolean
  body: string
  body_html: string
  body_long?: boolean
  edit_seconds_remaining?: number | null
  edit_diff_lines?: Array<{ kind: string; text: string }> | null
  signature_html?: string | null
  created_at: string
  edited_at: string | null
  last_edit_reason?: string | null
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
  deleted?: boolean
  small_action?: boolean
  whisper?: boolean
  wiki?: boolean
  staff_notice?: string | null
  restore_url?: string | null
  report_url: string | null
  raw_url?: string
  bookmarked: boolean
  bookmark_url: string | null
  bookmark?: {
    id: number
    update_url: string
    note: string | null
    remind_at_input: string | null
  } | null
  fork_topic_url?: string | null
  forked_topics?: Array<{ id: string; title: string; url: string }>
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
  anonymous?: boolean
  show_results?: boolean
  options?: Array<{ label: string; index: number }>
  results: Array<{ label: string; index: number; votes: number }>
  total_votes: number | null
  user_vote_index: number | null
  user_vote_indices?: number[]
  vote_url: string
  voters_url?: string | null
  export_url?: string | null
  close_url?: string | null
  revoke_url?: string | null
  closed_at?: string | null
  closes_at?: string | null
  share_url?: string | null
}

const props = defineProps<{
  topic: {
    id: string
    title: string
    author: string | null
    author_username?: string | null
    locked: boolean
    lock_reason?: string | null
    pinned: boolean
    pinned_until?: string | null
    bumped_at?: string | null
    prefix?: string | null
    hidden: boolean
    views_count: number
    watching: boolean
    notification_level?: 'watching' | 'tracking' | 'normal' | null
    muted?: boolean
    bookmarked: boolean
    can_moderate: boolean
    global_announcement?: boolean
    staff_notes?: Array<{ id: number; body: string; author: string; created_at: string }>
    staff_note_url?: string | null
    reply_bans?: Array<{ username: string; reason: string | null; expires_at: string | null }>
    can_invite?: boolean
    invite_url?: string | null
    share_as_pm_url?: string | null
    export_url?: string | null
    assigned_username?: string | null
    assigned_url?: string | null
    can_edit_poll?: boolean
    can_move: boolean
    can_edit: boolean
    featured: boolean
    wiki: boolean
    unlisted?: boolean
    archived_at?: string | null
    slow_mode_seconds: number | null
    auto_close_at?: string | null
    auto_open_at?: string | null
    auto_bump_at?: string | null
    auto_archive_at?: string | null
    solved_post_id: number | null
    tags: Array<{ name: string; slug: string; url: string; color_hex?: string | null; group_color_hex?: string | null }>
    tags_string: string
    section: { name: string; slug: string; url: string; color_hex?: string | null; icon?: string | null }
    rss_url?: string
    section_prefixes?: string[]
    tag_groups?: Array<{ name: string; slug: string; color_hex?: string | null; one_per_topic: boolean; tags: Array<{ name: string; slug: string; color_hex?: string | null }> }>
    linked_product_name?: string
    linked_product_url?: string
    bump_cooldown_remaining_seconds?: number | null
    slow_mode_remaining_seconds?: number | null
    reading_time_minutes?: number | null
    source_topic?: {
      title: string
      url: string
      floor_number: number
      author: string
    } | null
  }
  posts: PostItem[]
  pagination: PaginationMeta
  lastReadFloor?: number
  firstUnreadFloor?: number | null
  markUnreadUrl?: string | null
  jumpToUnreadUrl?: string | null
  canReply: boolean
  cannedResponses?: Array<{ title: string; body: string }>
  section_read_only?: boolean
  canMarkSolved: boolean
  reactionEmojis: string[]
  sections: SectionOption[]
  relatedTopics?: Array<{ id: string; title: string; url: string; replies_count: number }>
  reportTopicUrl: string | null
  poll: PollItem | null
  topicSearchQuery?: string
  postSort?: string
  canCloseOwn?: boolean
  topicBookmark?: {
    id: number
    update_url: string
    note: string | null
    remind_at_input: string | null
  } | null
  replyDraft?: string | null
  replyDraftUrl?: string | null
  warningRestrictions?: { post?: string | null; link?: string | null; pm?: string | null }
  subscriptionLevels?: SubscriptionLevelOption[]
  subscriptionUrl?: string | null
  meta?: { title: string; description: string | null; noindex?: boolean; url?: string | null; image?: string | null; poll_question?: string | null; twitter_card?: string | null; twitter_title?: string | null; twitter_description?: string | null; og_locale?: string | null; og_site_name?: string | null }
}>()

const page = usePage<{ auth: { user: { id: string; username: string } | null } }>()
const loggedIn = !!page.props.auth.user

const editingPostId = ref<number | null>(null)
const copiedPostId = ref<number | null>(null)
const editBody = ref('')
const editReason = ref('')
const editingTopic = ref(false)
const editTitle = ref(props.topic.title)
const editTags = ref(props.topic.tags_string)
const editPrefix = ref(props.topic.prefix || '')
const editTagPickerRef = ref<InstanceType<typeof TagGroupPicker> | null>(null)
const editTagError = ref('')
const replyLinkError = ref('')
const editLinkError = ref('')

function missingRequiredGroups(tags: string, groups?: Array<{ required?: boolean; tags: Array<{ name: string }> }>) {
  const names = tags.split(',').map((t) => t.trim()).filter(Boolean)
  return (groups || []).filter((group) => {
    if (!group.required) return false
    const groupNames = new Set(group.tags.map((t) => t.name))
    return !names.some((name) => groupNames.has(name))
  })
}

const editTagsReady = computed(() => missingRequiredGroups(editTags.value, props.topic.tag_groups).length === 0)

function containsLink(text: string) {
  return /https?:\/\/|www\./i.test(text)
}

const postBlocked = computed(() => !!props.warningRestrictions?.post)

const replyForm = useForm({
  post: {
    topic_id: props.topic.id,
    body: '',
    quoted_post_id: null as number | null,
    parent_post_id: null as number | null,
    whisper: false,
  },
})

const replyBodyHasBlockedLink = computed(() =>
  !!(props.warningRestrictions?.link && containsLink(replyForm.post.body))
)

const editBodyHasBlockedLink = computed(() =>
  !!(props.warningRestrictions?.link && containsLink(editBody.value))
)

const canSubmitReply = computed(() => !postBlocked.value && !replyBodyHasBlockedLink.value)

const sharePmOpen = ref(false)
const sharePmUsername = ref('')
const sharePmMessage = ref('')
const editPollQuestion = ref(props.poll?.question || '')
const editPollOptions = ref(props.poll?.options?.map((o) => o.label).join('\n') || '')
const editPollClosesDays = ref('')

const quotePreviews = ref<QuotedPost[]>([])
const replyPreview = ref<{ id: number; floor_number: number; author: string } | null>(null)
const moveSectionSlug = ref('')
const mergeTargetId = ref('')
const splitSectionSlug = ref('')
const showPollVoters = ref(false)
const pollVoters = ref<Array<{ label: string; index: number; voters: string[] }>>([])
const pollShareCopied = ref(false)
const slowModeSeconds = ref(props.topic.slow_mode_seconds || 0)
const slowModeRemaining = ref(props.topic.slow_mode_remaining_seconds || 0)
const effectiveCanReply = computed(() => props.canReply && slowModeRemaining.value <= 0 && !postBlocked.value)
let slowModeTimer: ReturnType<typeof setInterval> | null = null
const autoCloseAt = ref('')
const autoOpenAt = ref('')
const autoBumpAt = ref('')
const autoArchiveAt = ref('')
const draftKey = `forum-reply-draft-${props.topic.id}`
const topicSearch = ref(props.topicSearchQuery || '')
const postSort = ref(props.postSort || 'oldest')
const selectionQuote = ref<{ post: PostItem; text: string; top: number; left: number } | null>(null)
const selectedPollOptions = ref<number[]>(props.poll?.user_vote_indices || [])
const editingBookmark = ref(false)
const bookmarkNote = ref(props.topicBookmark?.note || '')
const bookmarkRemindAt = ref(props.topicBookmark?.remind_at_input || '')
const editingPostBookmarkId = ref<number | null>(null)
const postBookmarkNote = ref('')
const postBookmarkRemindAt = ref('')
const expandedPosts = ref<Record<number, boolean>>({})
const expandedDiffs = ref<Record<number, boolean>>({})
const lockReasonInput = ref('')
const assignPickerOpen = ref(false)
const assignQuery = ref('')
const assignSuggestions = ref<Array<{ username: string; display_name: string | null; avatar_url: string }>>([])
let assignSearchTimer: ReturnType<typeof setTimeout> | null = null
let draftSaveTimer: ReturnType<typeof setTimeout> | null = null

let topicKeydownHandler: ((event: KeyboardEvent) => void) | null = null

onMounted(() => {
  const saved = props.replyDraft || localStorage.getItem(draftKey)
  if (saved && !replyForm.post.body) {
    replyForm.post.body = saved
  }
  highlightCodeBlocks(document)
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
  } else if (hash.startsWith('#p-')) {
    const floor = Number(hash.replace('#p-', ''))
    if (floor > 0) {
      setTimeout(() => {
        const el = document.querySelector(`[data-floor="${floor}"]`)
        el?.scrollIntoView({ behavior: 'smooth', block: 'center' })
      }, 100)
    }
  }
  if (slowModeRemaining.value > 0) {
    slowModeTimer = setInterval(() => {
      if (slowModeRemaining.value > 0) slowModeRemaining.value -= 1
    }, 1000)
  }
  topicKeydownHandler = (event: KeyboardEvent) => {
    const target = event.target as HTMLElement | null
    if (target && ['INPUT', 'TEXTAREA', 'SELECT'].includes(target.tagName)) return
    if (event.key === 'r' && effectiveCanReply.value) {
      event.preventDefault()
      document.getElementById('reply-form')?.scrollIntoView({ behavior: 'smooth' })
    }
  }
  document.addEventListener('keydown', topicKeydownHandler)
})

onUnmounted(() => {
  if (slowModeTimer) clearInterval(slowModeTimer)
  if (topicKeydownHandler) document.removeEventListener('keydown', topicKeydownHandler)
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
  replyLinkError.value = ''
  if (props.warningRestrictions?.link && containsLink(replyForm.post.body)) {
    replyLinkError.value = props.warningRestrictions.link
    return
  }
  replyForm.post('/forum/posts', {
    preserveScroll: true,
    onSuccess: () => {
      replyForm.post.body = ''
      replyForm.post.quoted_post_id = null
      replyForm.post.parent_post_id = null
      quotePreviews.value = []
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

function buildQuoteBlock(post: PostItem) {
  const lines = post.body.split('\n').map((line) => `> ${line}`)
  return `> **#${post.floor_number} ${post.author}：**\n${lines.join('\n')}\n\n`
}

function quotePost(post: PostItem) {
  replyForm.post.quoted_post_id = post.id
  if (!quotePreviews.value.find((item) => item.id === post.id)) {
    quotePreviews.value.push({
      id: post.id,
      floor_number: post.floor_number,
      author: post.author,
      excerpt: post.body.slice(0, 120),
    })
  }
  const block = buildQuoteBlock(post)
  if (!replyForm.post.body.includes(`#${post.floor_number} ${post.author}`)) {
    replyForm.post.body = replyForm.post.body ? `${replyForm.post.body}\n\n${block}` : block
  }
  document.getElementById('reply-form')?.scrollIntoView({ behavior: 'smooth' })
}

function removeQuote(id: number) {
  const removed = quotePreviews.value.find((item) => item.id === id)
  quotePreviews.value = quotePreviews.value.filter((item) => item.id !== id)
  if (removed) {
    const marker = `#${removed.floor_number} ${removed.author}`
    const parts = replyForm.post.body.split(/\n\n+/)
    replyForm.post.body = parts.filter((part) => !part.includes(marker)).join('\n\n').trim()
  }
  if (replyForm.post.quoted_post_id === id) {
    replyForm.post.quoted_post_id = quotePreviews.value.at(-1)?.id ?? null
  }
}

function clearQuotes() {
  replyForm.post.quoted_post_id = null
  quotePreviews.value = []
}

function replyToPost(post: PostItem) {
  replyForm.post.parent_post_id = post.id
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

function updateAutoOpen() {
  router.patch(`/forum/topics/${props.topic.id}/auto_open`, { auto_open_at: autoOpenAt.value || null })
}

function updateAutoBump() {
  router.patch(`/forum/topics/${props.topic.id}/auto_bump`, { auto_bump_at: autoBumpAt.value || null })
}

function updateAutoArchive() {
  router.patch(`/forum/topics/${props.topic.id}/auto_archive`, { auto_archive_at: autoArchiveAt.value || null })
}

function restorePost(post: PostItem) {
  if (!post.restore_url) return
  router.post(post.restore_url, {}, { preserveScroll: true })
}

function reactionTitle(post: PostItem, emoji: string) {
  const users = post.reaction_users?.[emoji]
  return users?.length ? users.join('、') : ''
}

function copyPermalink(post: PostItem) {
  const url = `${window.location.origin}${routes.forumTopic(props.topic.id)}#p-${post.floor_number}`
  navigator.clipboard.writeText(url).then(() => {
    copiedPostId.value = post.id
    window.setTimeout(() => {
      if (copiedPostId.value === post.id) copiedPostId.value = null
    }, 2000)
  })
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
  editLinkError.value = ''
  if (props.warningRestrictions?.link && containsLink(editBody.value)) {
    editLinkError.value = props.warningRestrictions.link
    return
  }
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

const staffNoteBody = ref('')
const replyBanUsername = ref('')
const staffNoticePostId = ref<number | null>(null)
const staffNoticeText = ref('')
const replyBanReason = ref('')

function submitStaffNote() {
  if (!props.topic.staff_note_url || !staffNoteBody.value.trim()) return
  router.post(props.topic.staff_note_url, { body: staffNoteBody.value }, {
    preserveScroll: true,
    onSuccess: () => { staffNoteBody.value = '' },
  })
}

function banReply() {
  if (!replyBanUsername.value.trim()) return
  router.post(`/forum/topics/${props.topic.id}/reply_ban`, {
    username: replyBanUsername.value.trim(),
    reason: replyBanReason.value,
  }, {
    preserveScroll: true,
    onSuccess: () => {
      replyBanUsername.value = ''
      replyBanReason.value = ''
    },
  })
}

function unbanReply(username: string) {
  router.post(`/forum/topics/${props.topic.id}/reply_unban`, { username }, { preserveScroll: true })
}

function inviteWatcher() {
  if (!props.topic.invite_url || !inviteUsername.value.trim()) return
  router.post(props.topic.invite_url, { username: inviteUsername.value.trim() }, {
    preserveScroll: true,
    onSuccess: () => { inviteUsername.value = '' },
  })
}

function toggleMute() {
  router.post(`/forum/topics/${props.topic.id}/mute`, {}, { preserveScroll: true })
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
  if (action === 'assign') {
    assignPickerOpen.value = true
    assignQuery.value = props.topic.assigned_username || ''
    searchAssignees(assignQuery.value)
    return
  }
  if (action === 'lock' && !props.topic.locked) {
    const reason = window.prompt('锁定原因（可选）', lockReasonInput.value || '')
    if (reason === null) return
    lockReasonInput.value = reason
    router.post(`/forum/topics/${props.topic.id}/moderate`, { action_type: action, lock_reason: reason || undefined }, { preserveScroll: true })
    return
  }
  router.post(`/forum/topics/${props.topic.id}/moderate`, { action_type: action }, { preserveScroll: true })
}

function searchAssignees(query: string) {
  if (assignSearchTimer) clearTimeout(assignSearchTimer)
  assignSearchTimer = setTimeout(async () => {
    if (query.length < 1) {
      assignSuggestions.value = []
      return
    }
    try {
      const response = await fetch(`${routes.forumMentionSearch}?q=${encodeURIComponent(query)}&staff=1`, {
        headers: { Accept: 'application/json' },
        credentials: 'same-origin',
      })
      const data = await response.json()
      assignSuggestions.value = data.users || []
    } catch {
      assignSuggestions.value = []
    }
  }, 200)
}

function confirmAssign(username: string) {
  router.post(`/forum/topics/${props.topic.id}/moderate`, {
    action_type: 'assign',
    assignee_username: username,
  }, {
    preserveScroll: true,
    onSuccess: () => { assignPickerOpen.value = false },
  })
}

function isOwnPost(post: PostItem) {
  return loggedIn && page.props.auth.user?.username === post.author_username
}

function togglePostExpand(postId: number) {
  expandedPosts.value[postId] = !expandedPosts.value[postId]
}

function isPostExpanded(post: PostItem) {
  return !post.body_long || expandedPosts.value[post.id]
}

function moderatePost(post: PostItem, action: string, extra: Record<string, string> = {}) {
  router.post(`/forum/posts/${post.id}/moderate`, { action_type: action, ...extra }, { preserveScroll: true })
}

function changePostAuthor(post: PostItem) {
  const username = window.prompt('输入新作者用户名（Discourse Change Owner）')
  if (!username?.trim()) return
  moderatePost(post, 'change_author', { new_username: username.trim() })
}

function saveStaffNotice(post: PostItem) {
  if (!staffNoticeText.value.trim()) return
  moderatePost(post, 'set_staff_notice', { staff_notice: staffNoticeText.value.trim() })
  staffNoticePostId.value = null
  staffNoticeText.value = ''
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

function splitPost(post: PostItem) {
  if (!confirm(`确定从 #${post.floor_number} 起拆分为新主题？`)) return
  const title = window.prompt('新主题标题（留空使用默认）', '')
  router.post(`/forum/topics/${props.topic.id}/split`, {
    post_id: post.id,
    title: title || undefined,
    section_slug: splitSectionSlug.value || undefined,
  })
}

function forkTopic(post: PostItem) {
  if (!post.fork_topic_url) return
  const title = window.prompt('新主题标题（留空使用默认）', `回复：${props.topic.title}`)
  const body = window.prompt('补充说明（可选）', '') || undefined
  router.post(post.fork_topic_url, {
    title: title || undefined,
    body,
  })
}

async function loadPollVoters() {
  if (!props.poll?.voters_url) return
  showPollVoters.value = !showPollVoters.value
  if (!showPollVoters.value || pollVoters.value.length) return
  const res = await fetch(props.poll.voters_url, { credentials: 'same-origin' })
  if (res.ok) {
    const data = await res.json()
    pollVoters.value = data.voters_by_option || []
  }
}

function saveTopicEdit() {
  editTagError.value = ''
  if (!editTagsReady.value) {
    editTagError.value = '请从必填标签组中至少选择一个标签。'
    return
  }
  const payload: Record<string, unknown> = {
    title: editTitle.value,
    tags: editTags.value,
    prefix: editPrefix.value,
  }
  if (props.topic.can_edit_poll && props.poll) {
    payload.poll_question = editPollQuestion.value
    payload.poll_options = editPollOptions.value
    payload.poll_closes_days = editPollClosesDays.value
  }
  router.patch(`/forum/topics/${props.topic.id}`, { topic: payload }, {
    onSuccess: () => { editingTopic.value = false },
  })
}

function shareAsPm() {
  if (!props.topic.share_as_pm_url) return
  router.post(props.topic.share_as_pm_url, {
    recipient_username: sharePmUsername.value,
    message: sharePmMessage.value,
  }, {
    onSuccess: () => {
      sharePmOpen.value = false
      sharePmUsername.value = ''
      sharePmMessage.value = ''
    },
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

function revokePoll() {
  if (!props.poll?.revoke_url) return
  if (!confirm('确定撤销您的投票？')) return
  router.post(props.poll.revoke_url, {}, { preserveScroll: true })
}

function insertCanned(body: string) {
  replyForm.post.body = replyForm.post.body ? `${replyForm.post.body}\n\n${body}` : body
}

function searchInTopic() {
  router.get(routes.forumTopic(props.topic.id), { q: topicSearch.value || undefined, post_sort: postSort.value !== 'oldest' ? postSort.value : undefined }, { preserveScroll: true })
}

function changePostSort() {
  router.get(routes.forumTopic(props.topic.id), { q: topicSearch.value || undefined, post_sort: postSort.value !== 'oldest' ? postSort.value : undefined }, { preserveScroll: true })
}

function closeOwnTopic() {
  const reason = window.prompt('关闭原因（可选）', '') || undefined
  router.post(`/forum/topics/${props.topic.id}/close_own`, { lock_reason: reason }, { preserveScroll: true })
}

function reopenOwnTopic() {
  router.post(`/forum/topics/${props.topic.id}/reopen_own`, {}, { preserveScroll: true })
}

function onPostMouseUp(post: PostItem, event: MouseEvent) {
  const selection = window.getSelection()
  const text = selection?.toString().trim()
  if (!text || text.length < 2) {
    selectionQuote.value = null
    return
  }
  const target = event.currentTarget as HTMLElement
  if (!target.contains(selection?.anchorNode || null)) return
  const rect = selection?.getRangeAt(0).getBoundingClientRect()
  if (!rect) return
  selectionQuote.value = { post, text, top: rect.top + window.scrollY - 40, left: rect.left }
}

function quoteSelection() {
  if (!selectionQuote.value) return
  const { post, text } = selectionQuote.value
  replyForm.post.quoted_post_id = post.id
  if (!quotePreviews.value.find((item) => item.id === post.id)) {
    quotePreviews.value.push({
      id: post.id,
      floor_number: post.floor_number,
      author: post.author,
      excerpt: text.slice(0, 120),
    })
  }
  const block = `> **#${post.floor_number} ${post.author}：**\n${text.split('\n').map((line) => `> ${line}`).join('\n')}\n\n`
  replyForm.post.body = replyForm.post.body ? `${replyForm.post.body}\n\n${block}` : block
  selectionQuote.value = null
  window.getSelection()?.removeAllRanges()
  document.getElementById('reply-form')?.scrollIntoView({ behavior: 'smooth' })
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

async function copyPollShareLink() {
  if (!props.poll?.share_url) return
  const url = props.poll.share_url.startsWith('http')
    ? props.poll.share_url
    : `${window.location.origin}${props.poll.share_url}`
  try {
    await navigator.clipboard.writeText(url)
    pollShareCopied.value = true
    window.setTimeout(() => { pollShareCopied.value = false }, 2000)
  } catch {
    // ignore clipboard errors
  }
}
</script>

<template>
  <ReadingProgress />
  <ImageLightbox />
  <Head v-if="meta">
    <title>{{ meta.title }}</title>
    <meta v-if="meta.description" head-key="description" name="description" :content="meta.description" />
    <meta v-if="meta.noindex" head-key="robots" name="robots" content="noindex, nofollow" />
    <meta head-key="og:title" property="og:title" :content="meta.title" />
    <meta v-if="meta.description" head-key="og:description" property="og:description" :content="meta.description" />
    <meta head-key="og:type" property="og:type" content="article" />
    <meta v-if="meta.url" head-key="og:url" property="og:url" :content="meta.url" />
    <meta v-if="meta.twitter_card" head-key="twitter:card" name="twitter:card" :content="meta.twitter_card" />
    <meta v-if="meta.twitter_title" head-key="twitter:title" name="twitter:title" :content="meta.twitter_title" />
    <meta v-if="meta.twitter_description" head-key="twitter:description" name="twitter:description" :content="meta.twitter_description" />
    <link v-if="meta.url" head-key="canonical" rel="canonical" :href="meta.url" />
    <meta v-if="meta.image" head-key="og:image" property="og:image" :content="meta.image" />
    <meta v-if="meta.og_locale" head-key="og:locale" property="og:locale" :content="meta.og_locale" />
    <meta v-if="meta.og_site_name" head-key="og:site_name" property="og:site_name" :content="meta.og_site_name" />
  </Head>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: topic.section.name, href: topic.section.url },
    { label: topic.title, current: true },
  ]" />

  <p v-if="topic.source_topic" class="mb-4 rounded-lg border bg-muted/30 px-4 py-3 text-sm">
    本主题源自
    <Link :href="topic.source_topic.url" class="font-medium text-primary hover:underline">
      #{{ topic.source_topic.floor_number }} {{ topic.source_topic.author }} 的回复
    </Link>
    （{{ topic.source_topic.title }}）
  </p>

  <p v-if="topic.assigned_username && topic.assigned_url" class="mb-4 rounded-lg border border-orange-200 bg-orange-50 px-4 py-3 text-sm text-orange-900 dark:border-orange-900 dark:bg-orange-950/30">
    已指派给
    <Link :href="topic.assigned_url" class="font-medium hover:underline">@{{ topic.assigned_username }}</Link>
  </p>

  <div class="mb-4 flex flex-wrap items-start justify-between gap-3">
    <PageHeader
      :title="`${topic.prefix ? `[${topic.prefix}] ` : ''}${topic.pinned ? '[置顶] ' : ''}${topic.title}`"
      :subtitle="`${topic.author ? `作者 ${topic.author}` : ''}${topic.author ? ' · ' : ''}${topic.views_count} 次浏览${topic.reading_time_minutes ? ` · 约 ${topic.reading_time_minutes} 分钟阅读` : ''}`"
    />
    <div class="flex flex-wrap gap-2">
      <Button v-if="topic.rss_url" as-child variant="outline" size="sm">
        <a :href="topic.rss_url" target="_blank" rel="noopener">RSS</a>
      </Button>
      <Button v-if="topic.can_edit" type="button" variant="outline" size="sm" @click="editingTopic = !editingTopic">
        编辑主题
      </Button>
      <Button v-if="loggedIn" type="button" variant="outline" size="sm" @click="toggleBookmark">
        {{ topic.bookmarked ? '编辑书签' : '加入书签' }}
      </Button>
      <Button v-if="loggedIn && topic.bookmarked" type="button" variant="outline" size="sm" @click="removeBookmark">
        移除书签
      </Button>
      <Button v-if="loggedIn && subscriptionLevels?.length && subscriptionUrl" type="button" variant="outline" size="sm" class="px-1">
        <SubscriptionLevelSelect
          :options="subscriptionLevels"
          :subscription-url="subscriptionUrl"
          :watching="topic.watching"
          :notification-level="topic.notification_level"
        />
      </Button>
      <Button v-if="loggedIn" type="button" variant="outline" size="sm" @click="toggleMute">
        {{ topic.muted ? '取消静音' : '静音主题' }}
      </Button>
      <Button v-if="markUnreadUrl" type="button" variant="outline" size="sm" @click="markUnread">标为未读</Button>
      <Button v-if="canCloseOwn && !topic.locked" type="button" variant="outline" size="sm" @click="closeOwnTopic">关闭主题</Button>
      <Button v-if="canCloseOwn && topic.locked" type="button" variant="outline" size="sm" @click="reopenOwnTopic">重新打开</Button>
      <Button v-if="jumpToUnreadUrl" as-child variant="outline" size="sm">
        <Link :href="jumpToUnreadUrl">跳到未读</Link>
      </Button>
      <Button v-if="topic.share_as_pm_url" type="button" variant="outline" size="sm" @click="sharePmOpen = !sharePmOpen">
        私信分享
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
        <Button
          type="button"
          variant="outline"
          size="sm"
          :disabled="!!topic.bump_cooldown_remaining_seconds"
          :title="topic.bump_cooldown_remaining_seconds ? `冷却中（${topic.bump_cooldown_remaining_seconds}秒）` : undefined"
          @click="moderate('bump')"
        >
          提升主题
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
        <Button type="button" variant="outline" size="sm" @click="moderate(topic.global_announcement ? 'remove_global_announcement' : 'global_announcement')">
          {{ topic.global_announcement ? '取消全站公告' : '设为全站公告' }}
        </Button>
        <Button type="button" variant="outline" size="sm" @click="moderate(topic.unlisted ? 'list' : 'unlist')">
          {{ topic.unlisted ? '恢复列表显示' : '设为未列出' }}
        </Button>
        <Button type="button" variant="outline" size="sm" @click="moderate(topic.archived_at ? 'unarchive' : 'archive')">
          {{ topic.archived_at ? '取消归档' : '归档主题' }}
        </Button>
        <Button v-if="topic.assigned_username" type="button" variant="outline" size="sm" @click="moderate('unassign')">
          取消指派
        </Button>
        <Button v-else type="button" variant="outline" size="sm" @click="moderate('assign')">
          指派员工
        </Button>
        <Button v-if="topic.export_url" as-child variant="outline" size="sm">
          <a :href="topic.export_url" download>导出帖子 CSV</a>
        </Button>
      </template>
    </div>
  </div>

  <div v-if="assignPickerOpen" class="mb-4 max-w-md space-y-2 rounded-lg border p-4">
    <p class="text-sm font-medium">指派给员工（Discourse Assign）</p>
    <Input
      v-model="assignQuery"
      placeholder="搜索员工用户名"
      @input="searchAssignees(assignQuery)"
    />
    <ul v-if="assignSuggestions.length" class="max-h-40 overflow-auto rounded border text-sm">
      <li v-for="user in assignSuggestions" :key="user.username">
        <button
          type="button"
          class="flex w-full items-center gap-2 px-3 py-2 hover:bg-muted"
          @click="confirmAssign(user.username)"
        >
          <img v-if="user.avatar_url" :src="user.avatar_url" alt="" class="h-6 w-6 rounded-full">
          <span>@{{ user.username }}</span>
          <span v-if="user.display_name" class="text-muted-foreground">{{ user.display_name }}</span>
        </button>
      </li>
    </ul>
    <div class="flex gap-2">
      <Button
        type="button"
        size="sm"
        :disabled="!assignQuery.trim()"
        @click="confirmAssign(assignQuery.trim())"
      >
        确认指派
      </Button>
      <Button type="button" size="sm" variant="outline" @click="assignPickerOpen = false">取消</Button>
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
    <TagGroupPicker ref="editTagPickerRef" v-model="editTags" :tag-groups="topic.tag_groups" :max-tags="5" />
    <p v-if="editTagError" class="text-sm text-destructive">{{ editTagError }}</p>
    <template v-if="topic.can_edit_poll && poll">
      <Input v-model="editPollQuestion" placeholder="投票问题" />
      <Textarea v-model="editPollOptions" rows="4" placeholder="每行一个选项" />
      <Input v-model="editPollClosesDays" type="number" min="0" placeholder="关闭天数（0=不限）" />
    </template>
    <div class="flex gap-2">
      <Button type="button" size="sm" :disabled="!editTagsReady" @click="saveTopicEdit">保存</Button>
      <Button type="button" size="sm" variant="outline" @click="editingTopic = false">取消</Button>
    </div>
  </div>

  <div v-if="sharePmOpen && topic.share_as_pm_url" class="mb-4 max-w-md space-y-2 rounded-lg border p-4">
    <p class="text-sm font-medium">通过私信分享主题</p>
    <Input v-model="sharePmUsername" placeholder="收件人用户名" />
    <Textarea v-model="sharePmMessage" rows="2" placeholder="附言（可选）" />
    <div class="flex gap-2">
      <Button type="button" size="sm" @click="shareAsPm">发送</Button>
      <Button type="button" size="sm" variant="outline" @click="sharePmOpen = false">取消</Button>
    </div>
  </div>

  <div v-if="topic.tags.length" class="mb-4 flex flex-wrap gap-2">
    <Link
      v-for="tag in topic.tags"
      :key="tag.slug"
      :href="tag.url"
      class="inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs hover:bg-muted"
      :class="tag.color_hex ? '' : 'text-sky-700'"
      :style="tag.color_hex ? { borderColor: tag.color_hex, color: tag.color_hex } : undefined"
    >
      <span
        v-if="tag.group_color_hex"
        class="h-2 w-2 shrink-0 rounded-full"
        :style="{ backgroundColor: tag.group_color_hex }"
      />
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

  <section v-if="poll" id="poll" class="mb-6 max-w-xl rounded-lg border p-4">
    <div
      v-if="!poll.open"
      class="mb-3 rounded-md border border-amber-200 bg-amber-50 px-3 py-2 text-sm text-amber-900 dark:border-amber-800 dark:bg-amber-950/40 dark:text-amber-100"
    >
      投票已结束<span v-if="poll.closed_at">（{{ poll.closed_at }}）</span>，以下为最终结果。
    </div>
    <div class="mb-3 flex items-center justify-between gap-2">
      <h2 class="text-sm font-semibold">{{ poll.question }}</h2>
      <Button v-if="poll.close_url" type="button" variant="outline" size="sm" @click="closePoll">关闭投票</Button>
    </div>
    <p v-if="poll.multiple_choice" class="mb-2 text-xs text-muted-foreground">多选（最多 {{ poll.max_choices }} 项）</p>
    <p v-if="poll.anonymous" class="mb-2 text-xs text-muted-foreground">匿名投票：不公开投票者名单</p>
    <p v-if="poll.closes_at && poll.open" class="mb-2 text-xs text-muted-foreground">投票将于 {{ poll.closes_at }} 结束</p>
    <p v-if="poll.hide_results_until_vote && !poll.show_results && poll.open" class="mb-3 text-xs text-muted-foreground">
      投票后可查看结果
    </p>
    <div v-if="poll.show_results" class="space-y-2" :class="{ 'pointer-events-none opacity-75': !poll.open }">
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
    <div class="mt-2 flex flex-wrap gap-2">
      <Button v-if="poll.revoke_url" type="button" variant="outline" size="sm" @click="revokePoll">撤销投票</Button>
      <Button v-if="poll.voters_url" type="button" variant="outline" size="sm" @click="loadPollVoters">
        {{ showPollVoters ? '收起投票者' : '查看投票者' }}
      </Button>
      <Button v-if="poll.export_url" as-child variant="outline" size="sm">
        <a :href="poll.export_url" download>导出 CSV</a>
      </Button>
      <Button v-if="poll.share_url" type="button" variant="outline" size="sm" @click="copyPollShareLink">
        {{ pollShareCopied ? '已复制链接' : '复制投票链接' }}
      </Button>
    </div>
    <ul v-if="showPollVoters && pollVoters.length" class="mt-2 space-y-2 text-xs">
      <li v-for="group in pollVoters" :key="group.index">
        <span class="font-medium">{{ group.label }}：</span>
        <span class="text-muted-foreground">{{ group.voters.length ? group.voters.join('、') : '暂无' }}</span>
      </li>
    </ul>
  </section>

  <section v-if="topic.linked_product_url" class="mb-6 max-w-xl rounded-lg border p-4">
    <h2 class="mb-2 text-sm font-semibold">关联商品</h2>
    <Link :href="topic.linked_product_url" class="font-medium hover:underline">{{ topic.linked_product_name }}</Link>
  </section>

  <section v-if="relatedTopics?.length" class="mb-6 max-w-xl rounded-lg border p-4">
    <h2 class="mb-2 text-sm font-semibold">相关主题</h2>
    <ul class="space-y-1 text-sm">
      <li v-for="related in relatedTopics" :key="related.id">
        <Link :href="related.url" class="hover:underline">{{ related.title }}</Link>
        <span class="ml-2 text-xs text-muted-foreground">{{ related.replies_count }} 回复</span>
      </li>
    </ul>
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
      <label class="text-sm text-muted-foreground">拆分到分区：</label>
      <select v-model="splitSectionSlug" class="h-8 rounded-md border border-input bg-transparent px-2 text-sm">
        <option value="">当前分区</option>
        <option v-for="section in sections" :key="section.slug" :value="section.slug">
          {{ section.category ? `${section.category} / ` : '' }}{{ section.name }}
        </option>
      </select>
      <Input v-model="mergeTargetId" placeholder="合并到主题 ID" class="h-8 w-40" />
      <Button type="button" size="sm" variant="outline" :disabled="!mergeTargetId" @click="mergeTopic">合并</Button>
    </template>
    <template v-if="topic.can_moderate">
      <Input v-model.number="slowModeSeconds" type="number" min="0" class="h-8 w-24" placeholder="慢速秒" />
      <Button type="button" size="sm" variant="outline" @click="updateSlowMode">设置慢速</Button>
      <Input v-model="autoCloseAt" type="datetime-local" class="h-8 w-48" />
      <Button type="button" size="sm" variant="outline" @click="updateAutoClose">定时关闭</Button>
      <Input v-model="autoOpenAt" type="datetime-local" class="h-8 w-48" />
      <Button type="button" size="sm" variant="outline" @click="updateAutoOpen">定时开放</Button>
      <Input v-model="autoBumpAt" type="datetime-local" class="h-8 w-48" />
      <Button type="button" size="sm" variant="outline" @click="updateAutoBump">定时提升</Button>
      <Input v-model="autoArchiveAt" type="datetime-local" class="h-8 w-48" />
      <Button type="button" size="sm" variant="outline" @click="updateAutoArchive">定时归档</Button>
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
  <template v-if="slowModeRemaining > 0">
    慢速模式冷却中，请等待 {{ slowModeRemaining }} 秒后再回复。
  </template>
  <template v-else>
    慢速模式：同一用户需间隔 {{ topic.slow_mode_seconds }} 秒才能再次回复。
  </template>
  </p>
  <p v-if="topic.archived_at" class="mb-4 rounded-md border border-slate-200 bg-slate-50 px-4 py-3 text-sm text-slate-800">
    此主题已于 {{ topic.archived_at }} 归档，仅作者与版主可见。
  </p>
  <p v-if="topic.unlisted" class="mb-4 rounded-md border border-violet-200 bg-violet-50 px-4 py-3 text-sm text-violet-900">
    此主题为未列出状态，不会出现在公开列表中，但持有链接的用户仍可访问。
  </p>

  <p v-if="topic.auto_close_at" class="mb-4 rounded-md border border-orange-200 bg-orange-50 px-4 py-3 text-sm text-orange-900">
    将于 {{ topic.auto_close_at }} 自动关闭。
  </p>
  <p v-if="topic.auto_open_at" class="mb-4 rounded-md border border-green-200 bg-green-50 px-4 py-3 text-sm text-green-900">
    将于 {{ topic.auto_open_at }} 自动重新开放。
  </p>
  <p v-if="topic.auto_bump_at" class="mb-4 rounded-md border border-indigo-200 bg-indigo-50 px-4 py-3 text-sm text-indigo-900">
    将于 {{ topic.auto_bump_at }} 自动提升。
  </p>
  <p v-if="topic.auto_archive_at" class="mb-4 rounded-md border border-slate-200 bg-slate-50 px-4 py-3 text-sm text-slate-800">
    将于 {{ topic.auto_archive_at }} 自动归档。
  </p>
  <p v-if="topic.locked" class="mb-4 rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900 dark:border-amber-900 dark:bg-amber-950 dark:text-amber-100">
    此主题已锁定，无法回复。
    <span v-if="topic.lock_reason" class="mt-1 block font-medium">原因：{{ topic.lock_reason }}</span>
  </p>

  <p v-if="topic.global_announcement" class="mb-4 rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900 dark:border-amber-900 dark:bg-amber-950 dark:text-amber-100">
    此主题为全站公告，将在全站顶部展示。
  </p>

  <section v-if="topic.can_moderate && topic.staff_notes?.length" class="mb-4 rounded-lg border border-dashed border-amber-300 bg-amber-50/50 p-4 dark:border-amber-800 dark:bg-amber-950/20">
    <h2 class="mb-2 text-sm font-semibold text-amber-900 dark:text-amber-100">员工备注（仅版主可见）</h2>
    <ul class="space-y-2 text-sm">
      <li v-for="note in topic.staff_notes" :key="note.id" class="rounded border bg-background/80 p-2">
        <p class="text-muted-foreground text-xs">{{ note.author }} · {{ note.created_at }}</p>
        <p class="mt-1 whitespace-pre-wrap">{{ note.body }}</p>
      </li>
    </ul>
  </section>

  <section v-if="topic.can_moderate && topic.staff_note_url" class="mb-4 max-w-xl space-y-2 rounded-lg border p-4">
    <h2 class="text-sm font-semibold">添加员工备注</h2>
    <textarea v-model="staffNoteBody" rows="2" class="w-full rounded-md border px-2 py-1 text-sm" placeholder="仅员工可见" />
    <Button type="button" size="sm" :disabled="!staffNoteBody.trim()" @click="submitStaffNote">保存备注</Button>
  </section>

  <section v-if="topic.can_moderate" class="mb-4 max-w-xl space-y-2 rounded-lg border p-4">
    <h2 class="text-sm font-semibold">主题回复禁言</h2>
    <div v-if="topic.reply_bans?.length" class="space-y-1 text-sm">
      <div v-for="ban in topic.reply_bans" :key="ban.username" class="flex items-center justify-between gap-2">
        <span>{{ ban.username }}<span v-if="ban.expires_at" class="text-muted-foreground"> · 至 {{ ban.expires_at }}</span></span>
        <button type="button" class="text-xs text-primary hover:underline" @click="unbanReply(ban.username)">解除</button>
      </div>
    </div>
    <div class="flex flex-wrap gap-2">
      <Input v-model="replyBanUsername" placeholder="用户名" class="max-w-[10rem]" />
      <Input v-model="replyBanReason" placeholder="原因（可选）" class="flex-1 min-w-[8rem]" />
      <Button type="button" size="sm" variant="outline" @click="banReply">禁止回复</Button>
    </div>
  </section>

  <section v-if="topic.can_invite && topic.invite_url" class="mb-4 max-w-xl space-y-2 rounded-lg border p-4">
    <h2 class="text-sm font-semibold">邀请关注</h2>
    <p class="text-xs text-muted-foreground">邀请用户关注此主题（Discourse 风格），对方将收到通知并自动设为「关注」。</p>
    <div class="flex flex-wrap gap-2">
      <Input v-model="inviteUsername" placeholder="用户名" class="max-w-[12rem]" />
      <Button type="button" size="sm" variant="outline" :disabled="!inviteUsername.trim()" @click="inviteWatcher">发送邀请</Button>
    </div>
  </section>

  <form class="mb-4 flex max-w-md flex-wrap items-center gap-2" @submit.prevent="searchInTopic">
    <Input v-model="topicSearch" placeholder="在此主题内搜索帖子…" class="min-w-[12rem] flex-1" />
    <select v-model="postSort" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm" @change="changePostSort">
      <option value="oldest">最早优先</option>
      <option value="recent">最新优先</option>
    </select>
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
        :data-floor="post.floor_number"
        class="rounded-lg border p-4"
        :class="[
          post.small_action ? 'border-dashed bg-muted/20 text-sm italic' : '',
          post.whisper ? 'border-amber-400 bg-amber-50/40 dark:bg-amber-950/20' : '',
          post.hidden ? 'opacity-60 border-dashed' : '',
          post.deleted ? 'opacity-50 border-dashed bg-muted/30' : '',
          post.is_solved ? 'border-green-400 bg-green-50/50 dark:bg-green-950/20' : '',
        ]"
        :style="{ marginLeft: `${post.depth * 1.5}rem` }"
      >
      <div v-if="post.whisper" class="mb-2 text-xs font-medium text-amber-700 dark:text-amber-300">员工私语（仅员工可见）</div>
      <div v-if="post.small_action" class="mb-2 text-xs font-medium text-muted-foreground">系统操作</div>
      <div v-if="post.small_action" class="text-sm text-muted-foreground">
        {{ post.body }}
        <span class="ml-2 text-xs not-italic">— {{ post.author }}, {{ post.created_at }}</span>
      </div>
      <div v-else class="mb-3 flex items-start gap-3">
        <img :src="post.avatar_url" :alt="post.author" class="h-9 w-9 shrink-0 rounded-full" />
        <div class="min-w-0 flex-1">
          <div class="flex items-center justify-between gap-2 text-sm text-muted-foreground">
            <div>
              <span class="font-medium text-foreground">#{{ post.floor_number }}</span>
              <span v-if="post.is_solved" class="ml-2 text-xs text-green-600">[已解决]</span>
              <span class="mx-2">·</span>
              <UserHoverCard v-if="post.author_card_url" :username="post.author_username" :card-url="post.author_card_url">
                <Link :href="post.author_url" class="font-medium text-foreground hover:underline">{{ post.author }}</Link>
              </UserHoverCard>
              <Link v-else :href="post.author_url" class="font-medium text-foreground hover:underline">{{ post.author }}</Link>
              <span
                v-if="post.author_forum_title && post.author_flair_color"
                class="ml-1 rounded px-1.5 py-0.5 text-[10px] font-medium text-white"
                :style="{ backgroundColor: post.author_flair_color }"
              >{{ post.author_forum_title }}</span>
              <span
                v-for="badge in post.author_badges || []"
                :key="badge.name"
                class="ml-1 rounded border px-1 text-[10px]"
                :style="badge.color ? { borderColor: badge.color, color: badge.color } : undefined"
                :title="badge.granted_at ? `${badge.name} · ${badge.granted_at}` : badge.name"
              >{{ badge.icon || badge.name }}<span v-if="badge.granted_at" class="opacity-70">·{{ badge.granted_at }}</span></span>
              <span v-if="post.verified_purchaser" class="ml-1 rounded border border-green-300 bg-green-50 px-1 text-[10px] text-green-700">认证买家</span>
              <span class="mx-2">·</span>
              <span>{{ post.created_at }}</span>
              <span v-if="post.edited_at" class="ml-2">
                （已编辑 {{ post.edited_at }}<span v-if="post.last_edit_reason">：{{ post.last_edit_reason }}</span>
                <button v-if="post.edit_diff_lines?.length" type="button" class="hover:underline" @click="expandedDiffs[post.id] = !expandedDiffs[post.id]">
                  {{ expandedDiffs[post.id] ? '收起改动' : '查看改动' }}
                </button>
                <Link v-if="post.edits_url" :href="post.edits_url" class="hover:underline">历史</Link>）
              </span>
              <span v-if="post.wiki" class="ml-2 text-xs text-blue-600">[Wiki 帖]</span>
              <span v-if="post.hidden" class="ml-2 text-amber-600">[已隐藏]</span>
              <span v-if="post.deleted" class="ml-2 text-destructive">[已删除]</span>
            </div>
            <div class="flex gap-2">
              <button v-if="effectiveCanReply" type="button" class="text-xs hover:underline" @click="quotePost(post)">引用</button>
              <button v-if="post.fork_topic_url" type="button" class="text-xs hover:underline" @click="forkTopic(post)">转为新主题</button>
              <button type="button" class="text-xs hover:underline" @click="copyPermalink(post)">
                {{ copiedPostId === post.id ? '已复制' : '复制链接' }}
              </button>
              <button v-if="effectiveCanReply" type="button" class="text-xs hover:underline" @click="replyToPost(post)">回复</button>
              <a v-if="post.raw_url" :href="post.raw_url" target="_blank" rel="noopener" class="text-xs hover:underline">原文</a>
              <button v-if="post.bookmark_url" type="button" class="text-xs hover:underline" @click="togglePostBookmark(post)">
                {{ post.bookmarked ? '编辑书签' : '书签' }}
              </button>
              <button v-if="post.bookmarked && post.bookmark_url" type="button" class="text-xs hover:underline" @click="removePostBookmark(post)">移除书签</button>
              <button v-if="canMarkSolved && !post.is_solved" type="button" class="text-xs text-green-600 hover:underline" @click="markSolved(post)">标为已解决</button>
              <button v-if="topic.can_move && post.floor_number > 1" type="button" class="text-xs hover:underline" @click="splitPost(post)">拆分主题</button>
              <Link v-if="post.report_url" :href="post.report_url" class="text-xs hover:underline">举报</Link>
              <button v-if="post.can_moderate" type="button" class="text-xs hover:underline" @click="moderatePost(post, post.hidden ? 'unhide' : 'hide')">
                {{ post.hidden ? '显示' : '隐藏' }}
              </button>
              <button v-if="post.can_moderate && !post.small_action" type="button" class="text-xs hover:underline" @click="staffNoticePostId = post.id; staffNoticeText = post.staff_notice || ''">
                员工提示
              </button>
              <button v-if="post.can_moderate && !post.small_action" type="button" class="text-xs hover:underline" @click="moderatePost(post, post.wiki ? 'disable_wiki' : 'enable_wiki')">
                {{ post.wiki ? '关闭 Wiki' : 'Wiki 帖' }}
              </button>
              <button v-if="post.can_moderate && !post.small_action" type="button" class="text-xs hover:underline" @click="changePostAuthor(post)">更改作者</button>
              <button v-if="post.can_moderate && post.staff_notice" type="button" class="text-xs hover:underline" @click="moderatePost(post, 'clear_staff_notice')">清除提示</button>
              <button v-if="post.can_edit && editingPostId !== post.id" type="button" class="text-xs hover:underline" @click="startEdit(post)">编辑</button>
              <button v-if="post.can_delete && !post.deleted" type="button" class="text-xs text-destructive hover:underline" @click="deletePost(post)">删除</button>
              <button v-if="post.restore_url" type="button" class="text-xs text-green-600 hover:underline" @click="restorePost(post)">恢复</button>
            </div>
          </div>

          <div v-if="staffNoticePostId === post.id" class="mb-3 space-y-2 rounded border bg-muted/30 p-3">
            <textarea v-model="staffNoticeText" rows="2" class="w-full rounded-md border px-2 py-1 text-sm" placeholder="员工提示（所有人可见）" />
            <div class="flex gap-2">
              <Button type="button" size="sm" @click="saveStaffNotice(post)">保存提示</Button>
              <Button type="button" size="sm" variant="outline" @click="staffNoticePostId = null">取消</Button>
            </div>
          </div>

          <div v-if="post.staff_notice" class="mb-3 rounded-md border border-amber-300 bg-amber-50 px-3 py-2 text-sm text-amber-900 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-100">
            {{ post.staff_notice }}
          </div>

          <blockquote v-if="post.quoted_post" class="mb-3 mt-2 border-l-2 border-muted pl-3 text-sm text-muted-foreground">
            <a :href="`#post-${post.quoted_post.id}`" class="hover:underline">
              <span class="font-medium">#{{ post.quoted_post.floor_number }} {{ post.quoted_post.author }}：</span>
              {{ post.quoted_post.excerpt }}
            </a>
          </blockquote>
          <div v-if="post.forked_topics?.length" class="mb-2 text-xs text-muted-foreground">
            已衍生主题：
            <template v-for="(forked, index) in post.forked_topics" :key="forked.id">
              <Link :href="forked.url" class="text-primary hover:underline">{{ forked.title }}</Link><span v-if="index < post.forked_topics!.length - 1">、</span>
            </template>
          </div>

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
            <p v-if="editLinkError" class="text-sm text-destructive">{{ editLinkError }}</p>
            <p v-else-if="editBodyHasBlockedLink" class="text-sm text-destructive">{{ warningRestrictions?.link }}</p>
            <div class="flex gap-2">
              <Button type="button" size="sm" :disabled="editBodyHasBlockedLink" @click="saveEdit(post)">保存</Button>
              <Button type="button" size="sm" variant="outline" @click="cancelEdit">取消</Button>
            </div>
          </div>
          <div v-else class="mt-2">
            <div
              v-if="expandedDiffs[post.id] && post.edit_diff_lines?.length"
              class="mb-2 space-y-0.5 rounded border bg-muted/30 p-2 font-mono text-xs"
            >
              <div
                v-for="(line, i) in post.edit_diff_lines"
                :key="i"
                :class="line.kind === 'added' ? 'text-green-700' : line.kind === 'removed' ? 'text-red-700 line-through' : 'text-muted-foreground'"
              >
                {{ line.kind === 'added' ? '+' : line.kind === 'removed' ? '-' : ' ' }} {{ line.text }}
              </div>
            </div>
            <div
              class="prose prose-sm max-w-none text-sm dark:prose-invert"
              :class="post.body_long && !isPostExpanded(post) ? 'max-h-64 overflow-hidden relative' : ''"
              v-html="post.body_html"
              @mouseup="(event) => onPostMouseUp(post, event)"
            />
            <button
              v-if="post.body_long"
              type="button"
              class="mt-2 text-xs text-primary hover:underline"
              @click="togglePostExpand(post.id)"
            >
              {{ isPostExpanded(post) ? '收起' : '展开全文' }}
            </button>
          </div>
          <p v-if="post.edit_seconds_remaining && post.can_edit" class="mt-1 text-xs text-muted-foreground">
            编辑窗口剩余 {{ post.edit_seconds_remaining }} 秒
          </p>
          <div v-if="post.signature_html" class="mt-3 border-t pt-2 text-xs text-muted-foreground prose prose-sm max-w-none" v-html="post.signature_html" />

          <div class="mt-3 flex flex-wrap items-center gap-2" v-if="!post.small_action">
            <span v-if="post.reactions_total" class="text-xs text-muted-foreground">{{ post.reactions_total }} 个反应</span>
            <template v-if="loggedIn && !isOwnPost(post)">
              <ReactionUsersPopover
                v-for="emoji in reactionEmojis"
                :key="emoji"
                v-show="post.reaction_counts[emoji]"
                :emoji="emoji"
                :count="post.reaction_counts[emoji] || 0"
                :users="post.reaction_users?.[emoji] || []"
              />
              <button
                v-for="emoji in reactionEmojis"
                :key="`btn-${emoji}`"
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
              <ReactionUsersPopover
                v-for="emoji in reactionEmojis"
                :key="emoji"
                v-show="post.reaction_counts[emoji]"
                :emoji="emoji"
                :count="post.reaction_counts[emoji] || 0"
                :users="post.reaction_users?.[emoji] || []"
              />
            </template>
          </div>
        </div>
      </div>
    </article>
    </template>
  </div>

  <Pagination :pagination="pagination" :base-path="routes.forumTopic(topic.id)" />

  <p v-if="section_read_only" class="mb-4 rounded-md border border-slate-300 bg-slate-50 px-4 py-3 text-sm text-slate-800 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-100">
    此分区为只读模式，普通用户无法回复（版主除外）。
  </p>

  <p v-if="warningRestrictions?.post && canReply" class="mb-4 max-w-2xl rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-100">
    {{ warningRestrictions.post }}
  </p>

  <section v-if="effectiveCanReply" id="reply-form" class="mt-8 max-w-2xl">
    <h2 class="mb-3 text-sm font-semibold">回复</h2>
    <div v-if="cannedResponses?.length" class="mb-3 flex flex-wrap gap-2">
      <span class="self-center text-xs text-muted-foreground">罐头回复：</span>
      <Button
        v-for="(item, index) in cannedResponses"
        :key="index"
        type="button"
        variant="outline"
        size="sm"
        @click="insertCanned(item.body)"
      >
        {{ item.title }}
      </Button>
    </div>
    <div v-if="replyPreview" class="mb-3 rounded-md border bg-muted/40 p-3 text-sm">
      <div class="flex items-start justify-between gap-2">
        <p>回复 #{{ replyPreview.floor_number }} {{ replyPreview.author }}</p>
        <button type="button" class="text-xs text-muted-foreground hover:underline" @click="clearReplyTarget">清除</button>
      </div>
    </div>
    <div v-if="quotePreviews.length" class="mb-3 space-y-2">
      <div
        v-for="quote in quotePreviews"
        :key="quote.id"
        class="rounded-md border bg-muted/40 p-3 text-sm"
      >
        <div class="flex items-start justify-between gap-2">
          <p>
            引用 #{{ quote.floor_number }} {{ quote.author }}：
            {{ quote.excerpt }}
          </p>
          <button type="button" class="text-xs text-muted-foreground hover:underline" @click="removeQuote(quote.id)">移除</button>
        </div>
      </div>
      <button type="button" class="text-xs text-muted-foreground hover:underline" @click="clearQuotes">清除全部引用</button>
    </div>
    <form class="space-y-3" @submit.prevent="submitReply">
      <MarkdownEditor v-model="replyForm.post.body" :rows="6" placeholder="写下你的回复… 输入 @ 可提及用户" required />
      <p v-if="replyLinkError" class="text-sm text-destructive">{{ replyLinkError }}</p>
      <p v-else-if="replyBodyHasBlockedLink" class="text-sm text-destructive">{{ warningRestrictions?.link }}</p>
      <p v-else-if="warningRestrictions?.link" class="text-xs text-muted-foreground">{{ warningRestrictions.link }}</p>
      <label v-if="topic.can_moderate" class="flex items-center gap-2 text-sm">
        <input v-model="replyForm.post.whisper" type="checkbox">
        员工私语（仅员工可见）
      </label>
      <Button type="submit" :disabled="replyForm.processing || !canSubmitReply">发表回复</Button>
    </form>
  </section>

  <button
    v-if="selectionQuote && effectiveCanReply"
    type="button"
    class="fixed z-40 rounded-md border bg-popover px-2 py-1 text-xs shadow-md"
    :style="{ top: `${selectionQuote.top}px`, left: `${selectionQuote.left}px` }"
    @mousedown.prevent
    @click="quoteSelection"
  >
    引用选中
  </button>
</template>
