<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { confirm } from '@/lib/arcoConfirm'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  reactionType: { emoji: string; name: string; score: number; position: number; active: boolean }
  submitUrl: string
  method?: 'post' | 'patch'
  backUrl: string
  deleteUrl?: string | null
}>()

const form = useForm({ reaction_type: { ...props.reactionType } })

function submit() {
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}

async function destroy() {
  const ok = await confirm({
    title: t('admin.reactionTypes.deleteTitle'),
    message: t('admin.reactionTypes.deleteConfirm'),
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
      <a-row :gutter="[16, 0]">
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.reactionTypes.emoji') }}</span>
            <a-input v-model="form.reaction_type.emoji" placeholder="👍" :input-attrs="{ required: true, maxlength: 40 }" allow-clear />
          </label>
        </a-col>
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.reactionTypes.name') }}</span>
            <a-input
              v-model="form.reaction_type.name"
              :placeholder="t('admin.reactionTypes.namePlaceholder')"
              :input-attrs="{ required: true, maxlength: 40 }"
              allow-clear
            />
          </label>
        </a-col>
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.reactionTypes.score') }}</span>
            <a-input-number v-model="form.reaction_type.score" class="w-full" />
          </label>
        </a-col>
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.reactionTypes.position') }}</span>
            <a-input-number v-model="form.reaction_type.position" :min="0" class="w-full" />
          </label>
        </a-col>
      </a-row>
      <a-checkbox v-model="form.reaction_type.active">{{ t('admin.reactionTypes.active') }}</a-checkbox>
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
