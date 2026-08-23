<script setup lang="ts">
import { computed, ref } from 'vue'
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination from '@/components/portal/Pagination.vue'
import Button from '@/components/ui/Button.vue'
import Textarea from '@/components/ui/Textarea.vue'
import { routes } from '@/lib/routes'
import { confirm } from '@/lib/useConfirm'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

export interface PendingPostItem {
  id: number
  author: string
  topic_title: string
  topic_url: string
  section_name: string
  excerpt: string
  created_at: string
  attachments?: Array<{ filename: string; human_size: string; download_url: string }>
  approve_url: string
  reject_url: string
}

interface PaginationMeta {
  page: number
  pages: number
  count: number
  from: number | null
  to: number | null
  prev: number | null
  next: number | null
}

const props = defineProps<{
  posts: PendingPostItem[]
  pagination: PaginationMeta
  reason_max_length: number
}>()

const selectedPostId = ref<number | null>(null)
const approvalConfirming = ref(false)
const localReasonError = ref('')
const approveForm = useForm({})
const rejectForm = useForm({ reason: '' })
const reasonError = computed(() => rejectForm.errors.reason || localReasonError.value)
const decisionBusy = computed(
  () => approvalConfirming.value || approveForm.processing || rejectForm.processing,
)

async function approve(url: string) {
  if (decisionBusy.value) return

  approvalConfirming.value = true
  let accepted = false
  try {
    accepted = await confirm({
      title: t('forum.moderation.approveTitle'),
      message: t('forum.moderation.approveConfirm'),
      confirmLabel: t('forum.moderation.approve'),
    })
  } finally {
    approvalConfirming.value = false
  }
  if (!accepted) return

  approveForm.post(url, { preserveScroll: true })
}

function openRejection(postId: number) {
  if (decisionBusy.value) return

  rejectForm.reset()
  rejectForm.clearErrors()
  localReasonError.value = ''
  selectedPostId.value = postId
}

function closeRejection() {
  if (rejectForm.processing) return
  resetRejection()
}

function resetRejection() {
  selectedPostId.value = null
  localReasonError.value = ''
  rejectForm.reset()
  rejectForm.clearErrors()
}

function reject(post: PendingPostItem) {
  if (decisionBusy.value) return

  const reason = rejectForm.reason.trim()
  if (!reason) {
    localReasonError.value = t('forum.moderation.reasonRequired')
    return
  }
  if (reason.length > props.reason_max_length) {
    localReasonError.value = t('forum.moderation.reasonTooLong', {
      count: props.reason_max_length,
    })
    return
  }

  localReasonError.value = ''
  rejectForm.reason = reason
  rejectForm.post(post.reject_url, {
    preserveScroll: true,
    onSuccess: resetRejection,
  })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('forum.moderation.approvalsTitle'), current: true },
  ]" />

  <PageHeader :title="t('forum.moderation.approvalsTitle')" :subtitle="t('forum.moderation.approvalsSubtitle')" />

  <p v-if="posts.length === 0" class="text-sm text-muted-foreground">{{ t('forum.moderation.noPendingPosts') }}</p>

  <ul v-else class="space-y-3">
    <li v-for="post in posts" :key="post.id" class="rounded-lg border p-4">
      <div class="flex flex-wrap items-start justify-between gap-2">
        <div class="min-w-0 space-y-1">
          <p class="text-sm text-muted-foreground">
            {{ post.section_name }} · {{ post.author }} · {{ post.created_at }}
          </p>
          <Link :href="post.topic_url" class="font-medium hover:underline">{{ post.topic_title }}</Link>
          <p class="text-sm text-muted-foreground whitespace-pre-wrap">{{ post.excerpt }}</p>
          <ul v-if="post.attachments?.length" class="mt-1 space-y-0.5 text-xs text-muted-foreground">
            <li v-for="attachment in post.attachments" :key="attachment.download_url">
              <a :href="attachment.download_url" class="hover:underline">{{ attachment.filename }}</a>
              <span> ({{ attachment.human_size }})</span>
            </li>
          </ul>
        </div>
        <div class="flex shrink-0 gap-2">
          <Button
            type="button"
            size="sm"
            :disabled="decisionBusy"
            @click="approve(post.approve_url)"
          >
            {{ t('forum.moderation.approve') }}
          </Button>
          <Button
            type="button"
            size="sm"
            variant="outline"
            :disabled="decisionBusy"
            @click="openRejection(post.id)"
          >
            {{ t('forum.moderation.reject') }}
          </Button>
        </div>
      </div>

      <form
        v-if="selectedPostId === post.id"
        class="mt-4 space-y-3 border-t pt-4"
        @submit.prevent="reject(post)"
      >
        <div class="space-y-1">
          <label :for="`approval-reason-${post.id}`" class="text-sm font-medium">
            {{ t('forum.moderation.reasonLabel') }}
          </label>
          <Textarea
            :id="`approval-reason-${post.id}`"
            v-model="rejectForm.reason"
            :maxlength="reason_max_length"
            :aria-describedby="`approval-reason-help-${post.id}`"
            :disabled="decisionBusy"
            required
          />
          <p
            :id="`approval-reason-help-${post.id}`"
            :class="reasonError ? 'text-destructive' : 'text-muted-foreground'"
            class="text-xs"
            :role="reasonError ? 'alert' : undefined"
          >
            {{ reasonError || t('forum.moderation.reasonHint', { count: reason_max_length }) }}
          </p>
        </div>
        <div class="flex flex-wrap gap-2">
          <Button type="submit" size="sm" :disabled="decisionBusy">
            {{ t('forum.moderation.confirmReject') }}
          </Button>
          <Button
            type="button"
            size="sm"
            variant="outline"
            :disabled="decisionBusy"
            @click="closeRejection"
          >
            {{ t('common.cancel') }}
          </Button>
        </div>
      </form>
    </li>
  </ul>

  <Pagination
    v-if="pagination.pages > 1"
    :pagination="pagination"
    :base-path="routes.forumModerationApprovals"
  />
</template>
