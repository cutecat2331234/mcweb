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
  content: { type: 'page' | 'article'; title: string; slug: string; lock_version: number }
  submitUrl: string
  backUrl: string
  replacementRequired: boolean
  replacementOptions: Array<{ value: string; label: string }>
}>()

const form = useForm({
  reason: '',
  confirmation: '',
  replacement_page_public_id: '',
  lock_version: props.content.lock_version,
  request_id: createIdempotencyKey(),
})

const canSubmit = computed(() =>
  form.reason.trim().length > 0
  && form.confirmation === props.content.title
  && (!props.replacementRequired || form.replacement_page_public_id.length > 0),
)

function submit() {
  if (!canSubmit.value) return
  form.post(props.submitUrl)
}
</script>

<template>
  <a-space direction="vertical" :size="16" fill>
    <a-page-header :title="title" :subtitle="content.title" :show-back="false">
      <template #extra>
        <a-button @click="router.visit(backUrl)">{{ t('common.cancel') }}</a-button>
      </template>
    </a-page-header>

    <a-card :bordered="true">
      <a-alert
        type="warning"
        show-icon
        :title="t('admin.website.recovery.discard_warning_title')"
      >
        {{ t('admin.website.recovery.discard_warning_body') }}
      </a-alert>

      <a-descriptions :column="{ xs: 1, sm: 2 }" bordered>
        <a-descriptions-item :label="t('admin.website.recovery.type')">
          {{ t(`admin.website.recovery.types.${content.type}`) }}
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.website.recovery.slug')">
          {{ content.slug }}
        </a-descriptions-item>
      </a-descriptions>

      <a-form :model="form" layout="vertical" @submit="submit">
        <a-form-item field="reason" :label="t('admin.website.recovery.reason')" required>
          <a-textarea
            v-model="form.reason"
            :max-length="1000"
            show-word-limit
            :auto-size="{ minRows: 3, maxRows: 7 }"
          />
        </a-form-item>
        <a-form-item
          v-if="replacementRequired"
          field="replacement_page_public_id"
          :label="t('admin.website.recovery.home_replacement')"
          :extra="t('admin.website.recovery.home_replacement_hint')"
          required
        >
          <a-select
            v-model="form.replacement_page_public_id"
            :options="replacementOptions"
            allow-search
          />
        </a-form-item>
        <a-form-item
          field="confirmation"
          :label="t('admin.website.recovery.confirmation')"
          :extra="t('admin.website.recovery.confirmation_hint', { title: content.title })"
          required
        >
          <a-input v-model="form.confirmation" autocomplete="off" />
        </a-form-item>
        <a-space wrap>
          <a-button
            type="primary"
            status="danger"
            html-type="submit"
            :loading="form.processing"
            :disabled="!canSubmit"
          >
            {{ t('admin.website.recovery.discard') }}
          </a-button>
          <a-button :disabled="form.processing" @click="router.visit(backUrl)">
            {{ t('common.cancel') }}
          </a-button>
        </a-space>
      </a-form>
    </a-card>
  </a-space>
</template>
