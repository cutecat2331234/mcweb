<script setup lang="ts">
import { computed } from 'vue'
import { router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { createIdempotencyKey } from '@/lib/idempotency'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()
const props = defineProps<{
  title: string
  content: { id: string; type: 'page' | 'article'; title: string; slug: string; status: string; lock_version: number }
  revision: {
    id: number
    revision_number: number
    event_type: string
    reason: string | null
    source_lock_version: number
    author: string | null
    created_at: string
    snapshot: Record<string, unknown>
    restoreUrl: string
  }
  canRestore: boolean
  backUrl: string
}>()

const form = useForm({
  reason: '',
  confirmation: '',
  lock_version: props.content.lock_version,
  request_id: createIdempotencyKey(),
})
const canSubmit = computed(() =>
  props.canRestore
  && form.reason.trim().length > 0
  && form.confirmation === props.content.title,
)
const snapshotText = computed(() => JSON.stringify(props.revision.snapshot, null, 2))

function restoreDraft() {
  if (!canSubmit.value) return
  form.post(props.revision.restoreUrl)
}
</script>

<template>
  <a-space direction="vertical" :size="16" fill>
    <a-page-header
      :title="title"
      :subtitle="`${content.title} · #${revision.revision_number}`"
      :show-back="false"
    >
      <template #extra>
        <a-button @click="router.visit(backUrl)">{{ t('common.back') }}</a-button>
      </template>
    </a-page-header>

    <a-card :bordered="true">
      <a-descriptions :column="{ xs: 1, sm: 2 }" bordered>
        <a-descriptions-item :label="t('admin.website.revisions.event')">
          {{ t(`admin.website.revisions.events.${revision.event_type}`, revision.event_type) }}
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.website.revisions.author')">{{ revision.author || '—' }}</a-descriptions-item>
        <a-descriptions-item :label="t('admin.website.revisions.createdAt')">{{ revision.created_at }}</a-descriptions-item>
        <a-descriptions-item :label="t('admin.website.revisions.sourceVersion')">{{ revision.source_lock_version }}</a-descriptions-item>
        <a-descriptions-item :label="t('admin.website.revisions.reason')">{{ revision.reason || '—' }}</a-descriptions-item>
      </a-descriptions>
      <a-divider />
      <a-collapse>
        <a-collapse-item :header="t('admin.website.revisions.snapshot')" key="snapshot">
          <a-textarea :model-value="snapshotText" readonly :auto-size="{ minRows: 12, maxRows: 28 }" />
        </a-collapse-item>
      </a-collapse>
    </a-card>

    <a-card v-if="canRestore" :title="t('admin.website.revisions.restoreAsDraft')" :bordered="true">
      <a-alert type="warning" show-icon :title="t('admin.website.revisions.restoreWarning')" />
      <a-form :model="form" layout="vertical" @submit="restoreDraft">
        <a-form-item field="reason" :label="t('admin.website.revisions.reason')" required>
          <a-textarea v-model="form.reason" :max-length="1000" show-word-limit :auto-size="{ minRows: 3, maxRows: 6 }" />
        </a-form-item>
        <a-form-item
          field="confirmation"
          :label="t('admin.website.recovery.confirmation')"
          :extra="t('admin.website.recovery.confirmation_hint', { title: content.title })"
          required
        >
          <a-input v-model="form.confirmation" autocomplete="off" />
        </a-form-item>
        <a-button type="primary" status="warning" html-type="submit" :loading="form.processing" :disabled="!canSubmit">
          {{ t('admin.website.revisions.restoreAsDraft') }}
        </a-button>
      </a-form>
    </a-card>
  </a-space>
</template>
