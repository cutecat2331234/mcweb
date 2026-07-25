<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { confirm } from '@/lib/arcoConfirm'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  phrase: { locale: string; key: string; value: string }
  localeOptions: Array<{ value: string; label: string }>
  submitUrl: string
  method?: 'post' | 'patch'
  backUrl: string
  deleteUrl?: string | null
}>()

const form = useForm({ phrase: { ...props.phrase } })

function submit() {
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}

async function destroy() {
  const ok = await confirm({
    title: t('admin.phrasesForm.deleteTitle'),
    message: t('admin.phrasesForm.deleteConfirm'),
    confirmLabel: t('admin.ui.delete'),
    variant: 'destructive',
  })
  if (!props.deleteUrl || !ok) return
  form.delete(props.deleteUrl)
}
</script>

<template>
  <a-page-header :title="title" :show-back="false" class="mb-4 !px-0" />
  <a-card class="max-w-3xl" :bordered="true">
    <form class="grid gap-4" @submit.prevent="submit">
      <a-row :gutter="[16, 0]">
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.phrasesForm.locale') }}</span>
            <a-select v-model="form.phrase.locale" :options="localeOptions" />
          </label>
        </a-col>
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.phrasesForm.key') }}</span>
            <a-input
              v-model="form.phrase.key"
              placeholder="mcweb.flash.report_resolved"
              :input-attrs="{ required: true }"
              allow-clear
            />
          </label>
        </a-col>
      </a-row>
      <a-alert type="info">{{ t('admin.phrasesForm.keyHint') }}</a-alert>
      <label class="admin-forum-field">
        <span>{{ t('admin.phrasesForm.value') }}</span>
        <a-textarea
          v-model="form.phrase.value"
          :auto-size="{ minRows: 3, maxRows: 10 }"
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
