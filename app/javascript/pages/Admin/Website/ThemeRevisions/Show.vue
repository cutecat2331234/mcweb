<script setup lang="ts">
import { computed } from 'vue'
import { router, useForm } from '@inertiajs/vue3'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { createIdempotencyKey } from '@/lib/idempotency'

defineOptions({ layout: AdminLayout })

type Difference = {
  path: string
  before: unknown
  after: unknown
  before_present: boolean
  after_present: boolean
}

const props = defineProps<{
  title: string
  theme: { name: string; key: string; active: boolean; lockVersion: number }
  revision: {
    revisionNumber: number
    eventType: string
    eventLabel: string
    actor: string | null
    reason: string | null
    createdAt: string
    snapshot: { name: string; key: string; tokens: Record<string, unknown>; active: boolean }
    difference: Difference[]
    predecessorRevisionNumber: number | null
    sourceRevisionNumber: number | null
    restoreUrl: string
  }
  canRestore: boolean
  backUrl: string
  copy: {
    back: string
    revision: string
    event: string
    actor: string
    reason: string
    created_at: string
    source_revision: string
    predecessor: string
    snapshot: string
    name: string
    key: string
    tokens: string
    differences: string
    path: string
    before: string
    after: string
    no_differences: string
    missing: string
    active: string
    inactive: string
    restore_title: string
    restore_warning: string
    restore_reason: string
    restore_confirmation: string
    restore_confirmation_hint: string
    restore_action: string
  }
}>()

const form = useForm({
  reason: '',
  confirmation: '',
  lock_version: props.theme.lockVersion,
  request_id: createIdempotencyKey(),
})

const targetConfirmation = computed(() => String(props.revision.revisionNumber))
const confirmationHint = computed(() => props.copy.restore_confirmation_hint
  .replace('__revision__', targetConfirmation.value))
const canSubmit = computed(() =>
  props.canRestore
  && form.reason.trim().length > 0
  && form.confirmation === targetConfirmation.value,
)
const tokensText = computed(() => JSON.stringify(props.revision.snapshot.tokens, null, 2))

function formatValue(value: unknown, present: boolean) {
  if (!present) return props.copy.missing
  if (typeof value === 'string') return value
  return JSON.stringify(value, null, 2)
}

function restoreRevision() {
  if (!canSubmit.value) return
  form.post(props.revision.restoreUrl)
}
</script>

<template>
  <a-space direction="vertical" :size="16" fill>
    <a-page-header
      :title="title"
      :subtitle="`${theme.name} · #${revision.revisionNumber}`"
      :show-back="false"
    >
      <template #extra>
        <a-button @click="router.visit(backUrl)">{{ copy.back }}</a-button>
      </template>
    </a-page-header>

    <a-card :bordered="true">
      <a-descriptions :column="{ xs: 1, sm: 2 }" bordered>
        <a-descriptions-item :label="copy.revision">#{{ revision.revisionNumber }}</a-descriptions-item>
        <a-descriptions-item :label="copy.event">{{ revision.eventLabel }}</a-descriptions-item>
        <a-descriptions-item :label="copy.actor">{{ revision.actor || '—' }}</a-descriptions-item>
        <a-descriptions-item :label="copy.created_at">{{ revision.createdAt }}</a-descriptions-item>
        <a-descriptions-item :label="copy.reason">{{ revision.reason || '—' }}</a-descriptions-item>
        <a-descriptions-item :label="copy.predecessor">
          {{ revision.predecessorRevisionNumber ? `#${revision.predecessorRevisionNumber}` : '—' }}
        </a-descriptions-item>
        <a-descriptions-item v-if="revision.sourceRevisionNumber" :label="copy.source_revision">
          #{{ revision.sourceRevisionNumber }}
        </a-descriptions-item>
      </a-descriptions>
    </a-card>

    <a-card :title="copy.differences" :bordered="true">
      <a-empty v-if="revision.difference.length === 0" :description="copy.no_differences" />
      <a-table
        v-else
        :data="revision.difference"
        row-key="path"
        :pagination="false"
        :bordered="{ cell: true }"
        :scroll="{ minWidth: 760 }"
      >
        <template #columns>
          <a-table-column :title="copy.path" data-index="path" :width="240" />
          <a-table-column :title="copy.before" :width="260">
            <template #cell="{ record }">
              <a-typography-paragraph code copyable>
                {{ formatValue(record.before, record.before_present) }}
              </a-typography-paragraph>
            </template>
          </a-table-column>
          <a-table-column :title="copy.after" :width="260">
            <template #cell="{ record }">
              <a-typography-paragraph code copyable>
                {{ formatValue(record.after, record.after_present) }}
              </a-typography-paragraph>
            </template>
          </a-table-column>
        </template>
      </a-table>
    </a-card>

    <a-card :title="copy.snapshot" :bordered="true">
      <a-descriptions :column="{ xs: 1, sm: 2 }" bordered>
        <a-descriptions-item :label="copy.name">{{ revision.snapshot.name }}</a-descriptions-item>
        <a-descriptions-item :label="copy.key">{{ revision.snapshot.key }}</a-descriptions-item>
        <a-descriptions-item :label="copy.active">
          {{ revision.snapshot.active ? copy.active : copy.inactive }}
        </a-descriptions-item>
      </a-descriptions>
      <a-divider />
      <a-collapse>
        <a-collapse-item :header="copy.tokens" key="tokens">
          <a-textarea :model-value="tokensText" readonly :auto-size="{ minRows: 10, maxRows: 28 }" />
        </a-collapse-item>
      </a-collapse>
    </a-card>

    <a-card v-if="canRestore" :title="copy.restore_title" :bordered="true">
      <a-alert type="warning" show-icon :title="copy.restore_warning" />
      <a-form :model="form" layout="vertical" @submit="restoreRevision">
        <a-form-item field="reason" :label="copy.restore_reason" required>
          <a-textarea
            v-model="form.reason"
            :max-length="1000"
            show-word-limit
            :auto-size="{ minRows: 3, maxRows: 6 }"
          />
        </a-form-item>
        <a-form-item field="confirmation" :label="copy.restore_confirmation" required>
          <a-input v-model="form.confirmation" autocomplete="off" />
          <template #extra>
            {{ confirmationHint }}
          </template>
        </a-form-item>
        <a-button
          type="primary"
          status="warning"
          html-type="submit"
          :loading="form.processing"
          :disabled="!canSubmit"
        >
          {{ copy.restore_action }}
        </a-button>
      </a-form>
    </a-card>
  </a-space>
</template>
