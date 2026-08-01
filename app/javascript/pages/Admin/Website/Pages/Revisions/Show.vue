<script setup lang="ts">
import { router } from '@inertiajs/vue3'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { Modal } from '@mcweb/ui'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  page: { id: string; title: string }
  revision: {
    id: number
    revision_number: number
    author: string | null
    created_at: string
    snapshot: Record<string, unknown>
    restoreUrl: string
  }
  backUrl: string
}>()
const snapshotText = computed(() => JSON.stringify(props.revision.snapshot, null, 2))

function restoreDraft() {
  Modal.warning({
    title: t('admin.website.revisions.restoreTitle'),
    content: t('admin.website.revisions.restoreConfirm', {
      number: props.revision.revision_number,
    }),
    okText: t('admin.website.revisions.restore'),
    cancelText: t('common.cancel'),
    hideCancel: false,
    onOk: () => router.post(props.revision.restoreUrl),
  })
}
</script>

<template>
  <a-space direction="vertical" :size="16" fill>
    <a-page-header
      :title="title"
      :subtitle="`${page.title} · #${revision.revision_number}`"
      :show-back="false"
    />
    <a-card :bordered="true">
      <a-descriptions :column="{ xs: 1, sm: 2 }" bordered>
        <a-descriptions-item :label="t('admin.website.revisions.author')">
          {{ revision.author || '—' }}
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.website.revisions.createdAt')">
          {{ revision.created_at }}
        </a-descriptions-item>
      </a-descriptions>
      <a-divider />
      <a-textarea
        :model-value="snapshotText"
        readonly
        :auto-size="{ minRows: 12, maxRows: 28 }"
      />
    </a-card>
    <a-space>
      <a-button type="primary" status="warning" @click="restoreDraft">
        {{ t('admin.website.revisions.restoreAsDraft') }}
      </a-button>
      <a-button @click="router.visit(backUrl)">{{ t('common.back') }}</a-button>
    </a-space>
  </a-space>
</template>
