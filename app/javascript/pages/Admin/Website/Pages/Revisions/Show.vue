<script setup lang="ts">
import { router } from '@inertiajs/vue3'
import { Modal } from '@mcweb/ui'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

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

function restoreDraft() {
  Modal.warning({
    title: 'Restore revision',
    content: `Restore revision #${props.revision.revision_number} as the current draft?`,
    okText: 'Restore',
    cancelText: 'Cancel',
    hideCancel: false,
    onOk: () => router.post(props.revision.restoreUrl),
  })
}
</script>

<template>
  <a-page-header
    :title="title"
    :subtitle="`${page.title} · #${revision.revision_number}`"
    :show-back="false"
  />
  <a-card :bordered="true">
    <a-descriptions :column="{ xs: 1, sm: 2 }" bordered>
      <a-descriptions-item label="Author">{{ revision.author || '—' }}</a-descriptions-item>
      <a-descriptions-item label="Created at">{{ revision.created_at }}</a-descriptions-item>
    </a-descriptions>
    <a-divider />
    <pre class="revision-snapshot">{{ JSON.stringify(revision.snapshot, null, 2) }}</pre>
  </a-card>
  <a-space class="mt-4">
    <a-button type="primary" status="warning" @click="restoreDraft">Restore as draft</a-button>
    <a-button @click="router.visit(backUrl)">Back</a-button>
  </a-space>
</template>

<style scoped>
.revision-snapshot {
  max-height: 65vh;
  margin: 0;
  padding: 16px;
  overflow: auto;
  color: var(--color-text-1);
  background: var(--color-fill-2);
  border-radius: 4px;
  white-space: pre-wrap;
  word-break: break-word;
}
</style>
