<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { confirm } from '@/lib/arcoConfirm'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  canned_response: { title: string; body: string }
  submitUrl: string
  method?: 'post' | 'patch'
  backUrl: string
  deleteUrl?: string | null
}>()

const form = useForm({ canned_response: { ...props.canned_response } })

function submit() {
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}

async function destroy() {
  const ok = await confirm({
    title: t('admin.cannedResponses.deleteTitle'),
    message: t('admin.cannedResponses.deleteConfirm'),
    confirmLabel: t('admin.ui.delete'),
    variant: 'destructive',
  })
  if (!props.deleteUrl || !ok) return
  form.delete(props.deleteUrl)
}
</script>

<template>
  <a-page-header :title="title" :show-back="false" class="mb-4 !px-0" />
  <a-card class="max-w-2xl" :bordered="true">
    <form class="grid gap-4" @submit.prevent="submit">
      <label class="admin-forum-field">
        <span>{{ t('admin.common.title') }}</span>
        <a-input v-model="form.canned_response.title" :input-attrs="{ required: true }" allow-clear />
      </label>
      <label class="admin-forum-field">
        <span>{{ t('admin.common.body') }}</span>
        <a-textarea
          v-model="form.canned_response.body"
          :auto-size="{ minRows: 6, maxRows: 14 }"
          :textarea-attrs="{ required: true }"
        />
      </label>
      <a-space wrap>
        <a-button html-type="submit" type="primary" :loading="form.processing">{{ t('admin.ui.save') }}</a-button>
        <a-button v-if="deleteUrl" type="primary" status="danger" @click="destroy">{{ t('admin.ui.delete') }}</a-button>
        <Link :href="backUrl" class="arco-btn arco-btn-outline arco-btn-size-medium no-underline">{{ t('admin.ui.back') }}</Link>
      </a-space>
    </form>
  </a-card>
</template>

<style scoped>
.admin-forum-field { display: grid; gap: 6px; color: var(--color-text-2); font-size: 14px; }
</style>
