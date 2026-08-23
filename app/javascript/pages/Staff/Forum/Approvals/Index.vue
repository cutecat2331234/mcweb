<script setup lang="ts">
import { computed, ref } from 'vue'
import { Link, router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Button,
  Card,
  FormItem,
  Modal,
  Pagination,
  Space,
  Tag,
  Textarea,
  TypographyParagraph,
  TypographyText,
  TypographyTitle,
} from '@mcweb/ui'

import StaffLayout from '@/layouts/StaffLayout.vue'
import { routes } from '@/lib/routes'
import { useUnsavedForm } from '@/lib/unsavedForms'

defineOptions({ layout: StaffLayout })

type PendingPostItem = {
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

type PaginationMeta = {
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

const { t } = useI18n()
const selectedPost = ref<PendingPostItem | null>(null)
const approvalForm = useForm({})
const rejectionForm = useForm({ reason: '' })
const rejectionDirty = computed(() => (
  selectedPost.value !== null && rejectionForm.reason.trim().length > 0
))
const unsavedRejection = useUnsavedForm(rejectionDirty)
const decisionBusy = computed(() => approvalForm.processing || rejectionForm.processing)

function approve(post: PendingPostItem) {
  if (decisionBusy.value) return
  Modal.confirm({
    title: t('staffWorkspace.forumApprovals.approveTitle'),
    content: t('staffWorkspace.forumApprovals.approveConfirm'),
    okText: t('staffWorkspace.forumApprovals.approve'),
    cancelText: t('common.cancel'),
    onOk: () => approvalForm.post(post.approve_url, { preserveScroll: true }),
  })
}

function openRejection(post: PendingPostItem) {
  rejectionForm.reset()
  rejectionForm.clearErrors()
  selectedPost.value = post
}

function closeRejection() {
  if (rejectionForm.processing) return
  rejectionForm.reset()
  rejectionForm.clearErrors()
  selectedPost.value = null
  unsavedRejection.saved()
}

function reject(): boolean {
  if (!selectedPost.value || rejectionForm.processing) return false
  rejectionForm.reason = rejectionForm.reason.trim()
  if (!rejectionForm.reason) {
    rejectionForm.setError('reason', t('staffWorkspace.forumApprovals.reasonRequired'))
    return false
  }
  rejectionForm.post(selectedPost.value.reject_url, {
    preserveScroll: true,
    onSuccess: closeRejection,
  })
  // Arco keeps the modal open while the Inertia request owns completion.
  return false
}

function changePage(page: number) {
  router.visit(`${routes.staffForumApprovals}?page=${page}`)
}
</script>

<template>
  <Space direction="vertical" fill :size="20">
    <div>
      <TypographyTitle :heading="3">{{ t('staffWorkspace.forumApprovals.title') }}</TypographyTitle>
      <TypographyParagraph type="secondary">
        {{ t('staffWorkspace.forumApprovals.subtitle') }}
      </TypographyParagraph>
    </div>

    <TypographyText v-if="posts.length === 0" type="secondary">
      {{ t('staffWorkspace.forumApprovals.empty') }}
    </TypographyText>

    <Card v-for="post in posts" v-else :key="post.id" :bordered="true">
      <Space direction="vertical" fill :size="12">
        <Space wrap :size="8">
          <Tag color="arcoblue">{{ post.section_name }}</Tag>
          <TypographyText>{{ post.author }}</TypographyText>
          <TypographyText type="secondary">{{ post.created_at }}</TypographyText>
        </Space>
        <Link :href="post.topic_url"><TypographyText bold>{{ post.topic_title }}</TypographyText></Link>
        <TypographyParagraph>{{ post.excerpt }}</TypographyParagraph>
        <Space v-if="post.attachments?.length" direction="vertical" fill :size="4">
          <a
            v-for="attachment in post.attachments"
            :key="attachment.download_url"
            :href="attachment.download_url"
          >
            {{ attachment.filename }} ({{ attachment.human_size }})
          </a>
        </Space>
        <Space :size="8">
          <Button type="primary" :loading="approvalForm.processing" @click="approve(post)">
            {{ t('staffWorkspace.forumApprovals.approve') }}
          </Button>
          <Button status="danger" :disabled="decisionBusy" @click="openRejection(post)">
            {{ t('staffWorkspace.forumApprovals.reject') }}
          </Button>
        </Space>
      </Space>
    </Card>

    <Pagination
      v-if="pagination.pages > 1"
      :current="pagination.page"
      :total="pagination.count"
      :page-size="25"
      show-total
      @change="changePage"
    />
  </Space>

  <Modal
    :visible="selectedPost !== null"
    :title="t('staffWorkspace.forumApprovals.reject')"
    :ok-text="t('staffWorkspace.forumApprovals.confirmReject')"
    :cancel-text="t('common.cancel')"
    :ok-loading="rejectionForm.processing"
    :on-before-ok="reject"
    @cancel="closeRejection"
  >
    <FormItem
      :label="t('staffWorkspace.forumApprovals.reasonLabel')"
      :validate-status="rejectionForm.errors.reason ? 'error' : undefined"
      :help="rejectionForm.errors.reason || t('staffWorkspace.forumApprovals.reasonHint', { count: reason_max_length })"
    >
      <Textarea
        v-model="rejectionForm.reason"
        :max-length="reason_max_length"
        show-word-limit
        allow-clear
      />
    </FormItem>
  </Modal>
</template>
