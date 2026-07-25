<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { confirm } from '@/lib/arcoConfirm'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  warning_template: { name: string; reason: string; points: number; expire_days: number | null }
  submitUrl: string
  method?: 'post' | 'patch'
  backUrl: string
  deleteUrl?: string | null
}>()

const form = useForm({ warning_template: { ...props.warning_template } })

function submit() {
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}

async function destroy() {
  const ok = await confirm({
    title: t('admin.warningTemplates.deleteTitle'),
    message: t('admin.warningTemplates.deleteConfirm'),
    confirmLabel: t('admin.ui.delete'),
    variant: 'destructive',
  })
  if (!props.deleteUrl || !ok) return
  form.delete(props.deleteUrl)
}
</script>

<template>
  <a-page-header :title="title" :show-back="false" class="mb-4 !px-0" />
  <a-card class="max-w-xl" :bordered="true">
    <form class="grid gap-4" @submit.prevent="submit">
      <label class="admin-forum-field">
        <span>{{ t('admin.warningTemplates.name') }}</span>
        <a-input v-model="form.warning_template.name" :input-attrs="{ required: true }" allow-clear />
      </label>
      <label class="admin-forum-field">
        <span>{{ t('admin.warningTemplates.reason') }}</span>
        <a-textarea v-model="form.warning_template.reason" :auto-size="{ minRows: 4, maxRows: 8 }" />
      </label>
      <a-row :gutter="[16, 0]">
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.warningTemplates.points') }}</span>
            <a-input-number v-model="form.warning_template.points" :min="0" :max="10" class="w-full" />
          </label>
        </a-col>
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.warningTemplates.expireDays') }}</span>
            <a-input-number
              :model-value="form.warning_template.expire_days ?? undefined"
              :min="0"
              class="w-full"
              @update:model-value="(value: number | undefined) => { form.warning_template.expire_days = value ?? null }"
            />
          </label>
        </a-col>
      </a-row>
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
