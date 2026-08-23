<script setup lang="ts">
import { computed, ref } from 'vue'
import { router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import HighRiskActionModal from '@/components/admin/HighRiskActionModal.vue'
import { createIdempotencyKey } from '@/lib/idempotency'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()
const props = defineProps<{
  title: string
  content: {
    id: string
    type: 'page' | 'article'
    type_label: string
    title: string
    slug: string
    status: string
    lock_version: number
    discarded_by: string | null
    discarded_at: string | null
    discard_reason: string | null
    purge_at: string | null
    revision_count: number
    confirmation: string
  }
  restoreBlockers: string[]
  purgeBlockers: string[]
  paths: { index: string; restore: string; authorizePurge: string; purge: string; revisions: string }
  permissions: { restore: boolean; purge: boolean }
}>()

const purgeVisible = ref(false)
const restoreForm = useForm({
  reason: '',
  confirmation: '',
  lock_version: props.content.lock_version,
  request_id: createIdempotencyKey(),
})
const canRestore = computed(() =>
  props.permissions.restore
  && props.restoreBlockers.length === 0
  && restoreForm.reason.trim().length > 0
  && restoreForm.confirmation === props.content.confirmation,
)

function restore() {
  if (!canRestore.value) return
  restoreForm.post(props.paths.restore)
}

function blockerLabel(code: string) {
  return t(`admin.website.recovery.blockers.${code}`, code)
}

function purgeCompleted(result: Record<string, unknown>) {
  const destination = typeof result.redirect_url === 'string' ? result.redirect_url : props.paths.index
  router.visit(destination)
}
</script>

<template>
  <a-space direction="vertical" :size="16" fill>
    <a-page-header :title="title" :subtitle="content.title" :show-back="false">
      <template #extra>
        <a-space wrap>
          <a-button @click="router.visit(paths.revisions)">
            {{ t('admin.website.revisions.title') }} ({{ content.revision_count }})
          </a-button>
          <a-button @click="router.visit(paths.index)">{{ t('common.back') }}</a-button>
        </a-space>
      </template>
    </a-page-header>

    <a-card :bordered="true">
      <a-descriptions :column="{ xs: 1, md: 2 }" bordered>
        <a-descriptions-item :label="t('admin.website.recovery.type')">{{ content.type_label }}</a-descriptions-item>
        <a-descriptions-item :label="t('admin.website.recovery.slug')">{{ content.slug }}</a-descriptions-item>
        <a-descriptions-item :label="t('admin.website.recovery.discarded_by')">{{ content.discarded_by || '—' }}</a-descriptions-item>
        <a-descriptions-item :label="t('admin.website.recovery.discarded_at')">{{ content.discarded_at || '—' }}</a-descriptions-item>
        <a-descriptions-item :label="t('admin.website.recovery.purge_deadline')">{{ content.purge_at || '—' }}</a-descriptions-item>
        <a-descriptions-item :label="t('admin.website.recovery.reason')">{{ content.discard_reason || '—' }}</a-descriptions-item>
      </a-descriptions>
    </a-card>

    <a-card v-if="permissions.restore" :title="t('admin.website.recovery.restore')" :bordered="true">
      <a-alert v-if="restoreBlockers.length" type="warning" show-icon>
        <a-list size="small" :bordered="false">
          <a-list-item v-for="blocker in restoreBlockers" :key="blocker">
            {{ blockerLabel(blocker) }}
          </a-list-item>
        </a-list>
      </a-alert>
      <a-form :model="restoreForm" layout="vertical" @submit="restore">
        <a-form-item field="reason" :label="t('admin.website.recovery.reason')" required>
          <a-textarea v-model="restoreForm.reason" :max-length="1000" show-word-limit :auto-size="{ minRows: 3, maxRows: 6 }" />
        </a-form-item>
        <a-form-item
          field="confirmation"
          :label="t('admin.website.recovery.confirmation')"
          :extra="t('admin.website.recovery.confirmation_hint', { title: content.confirmation })"
          required
        >
          <a-input v-model="restoreForm.confirmation" autocomplete="off" />
        </a-form-item>
        <a-button type="primary" html-type="submit" :loading="restoreForm.processing" :disabled="!canRestore">
          {{ t('admin.website.recovery.restore_as_draft') }}
        </a-button>
      </a-form>
    </a-card>

    <a-card v-if="permissions.purge" :title="t('admin.website.recovery.final_purge')" :bordered="true">
      <a-alert type="error" show-icon :title="t('admin.website.recovery.purge_warning')" />
      <a-list v-if="purgeBlockers.length" size="small" :bordered="false">
        <a-list-item v-for="blocker in purgeBlockers" :key="blocker">
          {{ blockerLabel(blocker) }}
        </a-list-item>
      </a-list>
      <a-button status="danger" :disabled="purgeBlockers.length > 0" @click="purgeVisible = true">
        {{ t('admin.website.recovery.final_purge') }}
      </a-button>
    </a-card>

    <HighRiskActionModal
      v-model:visible="purgeVisible"
      :title="t('admin.website.recovery.final_purge')"
      :authorization-url="paths.authorizePurge"
      :action-url="paths.purge"
      method="DELETE"
      requires-verification
      @completed="purgeCompleted"
    />
  </a-space>
</template>
