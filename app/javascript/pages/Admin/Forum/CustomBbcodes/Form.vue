<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { confirm } from '@/lib/arcoConfirm'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  custom_bbcode: { tag: string; replacement: string; sample: string; active: boolean }
  submitUrl: string
  method?: 'post' | 'patch'
  backUrl: string
  deleteUrl?: string | null
}>()

const form = useForm({ custom_bbcode: { ...props.custom_bbcode } })

function submit() {
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}

async function destroy() {
  const ok = await confirm({
    title: t('admin.customBbcodes.deleteTitle'),
    message: t('admin.customBbcodes.deleteConfirm'),
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
        <span>{{ t('admin.customBbcodes.tag') }}</span>
        <a-input
          v-model="form.custom_bbcode.tag"
          placeholder="note"
          :input-attrs="{ required: true, maxlength: 20 }"
          allow-clear
        />
        <small>{{ t('admin.customBbcodes.tagHint') }}</small>
      </label>
      <label class="admin-forum-field">
        <span>{{ t('admin.customBbcodes.replacement') }}</span>
        <a-textarea
          v-model="form.custom_bbcode.replacement"
          :auto-size="{ minRows: 4, maxRows: 10 }"
          :placeholder="'> 📌 {content}'"
          :textarea-attrs="{ required: true }"
        />
        <small>{{ t('admin.customBbcodes.replacementHint') }}</small>
      </label>
      <label class="admin-forum-field">
        <span>{{ t('admin.customBbcodes.sample') }}</span>
        <a-input v-model="form.custom_bbcode.sample" allow-clear />
      </label>
      <a-checkbox v-model="form.custom_bbcode.active">{{ t('admin.customBbcodes.active') }}</a-checkbox>
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
.admin-forum-field small { color: var(--color-text-3); }
</style>
