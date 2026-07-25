<script setup lang="ts">
import { computed } from 'vue'
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  tag: { id?: number; name: string; slug: string; description: string; staff_only: boolean; color_hex: string; canonical_tag_id?: number | null }
  canonicalTags?: Array<{ id: number; name: string }>
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
}>()

const form = useForm({ tag: { ...props.tag } })

const canonicalTagOptions = computed(() => [
  { value: '', label: t('admin.forms.tag.canonicalNone') },
  ...(props.canonicalTags || []).map((tag) => ({ value: String(tag.id), label: tag.name })),
])

function updateCanonicalTagId(value: string) {
  form.tag.canonical_tag_id = value ? Number(value) : null
}

function submit() {
  if (props.method === 'patch') form.patch(props.submitUrl)
  else form.post(props.submitUrl)
}
</script>

<template>
  <a-page-header :title="title" :show-back="false" class="mb-4 !px-0" />
  <a-card class="max-w-2xl" :bordered="true">
    <form class="grid gap-4" @submit.prevent="submit">
      <a-row :gutter="[16, 0]">
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.common.name') }}</span>
            <a-input v-model="form.tag.name" :input-attrs="{ required: true }" allow-clear />
          </label>
        </a-col>
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.forms.tag.slug') }}</span>
            <a-input v-model="form.tag.slug" :input-attrs="{ required: true }" allow-clear />
          </label>
        </a-col>
      </a-row>
      <label class="admin-forum-field">
        <span>{{ t('admin.common.description') }}</span>
        <a-textarea v-model="form.tag.description" :auto-size="{ minRows: 3, maxRows: 7 }" />
      </label>
      <label class="admin-forum-field">
        <span>{{ t('admin.common.colorHex') }}</span>
        <a-input v-model="form.tag.color_hex" placeholder="#22c55e" allow-clear />
      </label>
      <label v-if="canonicalTags?.length" class="admin-forum-field">
        <span>{{ t('admin.forms.tag.canonicalLabel') }}</span>
        <a-select
          :model-value="form.tag.canonical_tag_id == null ? '' : String(form.tag.canonical_tag_id)"
          :options="canonicalTagOptions"
          @change="updateCanonicalTagId"
        />
        <small>{{ t('admin.forms.tag.canonicalHint') }}</small>
      </label>
      <a-checkbox v-model="form.tag.staff_only">{{ t('admin.forms.tag.staffOnly') }}</a-checkbox>
      <a-space wrap>
        <a-button html-type="submit" type="primary" :loading="form.processing">{{ t('admin.ui.save') }}</a-button>
        <Link :href="backUrl" class="arco-btn arco-btn-outline arco-btn-size-medium no-underline">{{ t('admin.ui.back') }}</Link>
      </a-space>
    </form>
  </a-card>
</template>

<style scoped>
.admin-forum-field { display: grid; gap: 6px; color: var(--color-text-2); font-size: 14px; }
.admin-forum-field small { color: var(--color-text-3); }
</style>
