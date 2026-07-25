<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { confirm } from '@/lib/arcoConfirm'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  user_title: { min_posts: number; title: string }
  submitUrl: string
  method?: 'post' | 'patch'
  backUrl: string
  deleteUrl?: string | null
}>()

const form = useForm({ user_title: { ...props.user_title } })

function submit() {
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}

async function destroy() {
  const ok = await confirm({
    title: t('admin.userTitles.deleteTitle'),
    message: t('admin.userTitles.deleteConfirm'),
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
        <span>{{ t('admin.userTitles.title') }}</span>
        <a-input
          v-model="form.user_title.title"
          :input-attrs="{ required: true, maxlength: 100 }"
          allow-clear
        />
      </label>
      <label class="admin-forum-field">
        <span>{{ t('admin.userTitles.minPosts') }}</span>
        <a-input-number
          v-model="form.user_title.min_posts"
          :min="0"
          :input-attrs="{ required: true }"
          class="w-full"
        />
        <small>{{ t('admin.userTitles.minPostsHint') }}</small>
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
.admin-forum-field small { color: var(--color-text-3); }
</style>
