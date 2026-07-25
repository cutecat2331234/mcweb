<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { confirm } from '@/lib/arcoConfirm'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  notice: {
    title: string
    message: string
    style: string
    audience: string
    active: boolean
    dismissible: boolean
    min_trust_level: number | null
    max_trust_level: number | null
    position: number
    starts_at: string | null
    ends_at: string | null
  }
  styleOptions: Array<{ value: string; label: string }>
  audienceOptions: Array<{ value: string; label: string }>
  submitUrl: string
  method?: 'post' | 'patch'
  backUrl: string
  deleteUrl?: string | null
}>()

const form = useForm({ notice: { ...props.notice } })

function submit() {
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}

async function destroy() {
  const ok = await confirm({
    title: t('admin.notices.deleteTitle'),
    message: t('admin.notices.deleteConfirm'),
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
      <label class="admin-forum-field">
        <span>{{ t('admin.notices.titleLabel') }}</span>
        <a-input v-model="form.notice.title" :input-attrs="{ required: true, maxlength: 120 }" allow-clear />
      </label>
      <label class="admin-forum-field">
        <span>{{ t('admin.notices.message') }}</span>
        <a-textarea
          v-model="form.notice.message"
          :auto-size="{ minRows: 4, maxRows: 10 }"
          :textarea-attrs="{ required: true }"
        />
      </label>
      <a-row :gutter="[16, 0]">
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.notices.style') }}</span>
            <a-select v-model="form.notice.style" :options="styleOptions" />
          </label>
        </a-col>
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.notices.audience') }}</span>
            <a-select v-model="form.notice.audience" :options="audienceOptions" />
          </label>
        </a-col>
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.notices.minTrust') }}</span>
            <a-input-number
              :model-value="form.notice.min_trust_level ?? undefined"
              :min="0"
              :max="4"
              class="w-full"
              @update:model-value="(value: number | undefined) => { form.notice.min_trust_level = value ?? null }"
            />
          </label>
        </a-col>
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.notices.maxTrust') }}</span>
            <a-input-number
              :model-value="form.notice.max_trust_level ?? undefined"
              :min="0"
              :max="4"
              class="w-full"
              @update:model-value="(value: number | undefined) => { form.notice.max_trust_level = value ?? null }"
            />
          </label>
        </a-col>
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.notices.position') }}</span>
            <a-input-number v-model="form.notice.position" :min="0" class="w-full" />
          </label>
        </a-col>
      </a-row>
      <a-row :gutter="[16, 0]">
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.notices.startsAt') }}</span>
            <a-date-picker
              :model-value="form.notice.starts_at ?? undefined"
              show-time
              value-format="YYYY-MM-DDTHH:mm"
              format="YYYY-MM-DD HH:mm"
              class="w-full"
              allow-clear
              @update:model-value="(value: string | undefined) => { form.notice.starts_at = value ?? null }"
            />
          </label>
        </a-col>
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.notices.endsAt') }}</span>
            <a-date-picker
              :model-value="form.notice.ends_at ?? undefined"
              show-time
              value-format="YYYY-MM-DDTHH:mm"
              format="YYYY-MM-DD HH:mm"
              class="w-full"
              allow-clear
              @update:model-value="(value: string | undefined) => { form.notice.ends_at = value ?? null }"
            />
          </label>
        </a-col>
      </a-row>
      <a-space direction="vertical" align="start">
        <a-checkbox v-model="form.notice.active">{{ t('admin.notices.active') }}</a-checkbox>
        <a-checkbox v-model="form.notice.dismissible">{{ t('admin.notices.dismissible') }}</a-checkbox>
      </a-space>
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
