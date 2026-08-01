<script setup lang="ts">
import { router, useForm } from '@inertiajs/vue3'
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

function fieldError(field: string) {
  const errors = form.errors as Record<string, string | undefined>
  return errors[field] || errors[`reaction_type.${field}`]
}

function submit(event?: { errors?: unknown }) {
  if (event?.errors) return
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

function goBack() {
  router.visit(props.backUrl)
}
</script>

<template>
  <a-space direction="vertical" :size="16" fill>
    <a-page-header :title="title" :show-back="false">
      <template #extra>
        <a-button shape="round" @click="goBack">{{ t('admin.ui.back') }}</a-button>
      </template>
    </a-page-header>
    <a-card :bordered="true">
      <a-form :model="form.reaction_type" layout="vertical" @submit="submit">
        <a-grid :cols="{ xs: 1, sm: 2 }" :col-gap="16" :row-gap="4">
          <a-grid-item>
            <a-form-item
              field="emoji"
              :label="t('admin.reactionTypes.emoji')"
              :help="fieldError('emoji')"
              :validate-status="fieldError('emoji') ? 'error' : undefined"
            >
              <a-input
                v-model="form.reaction_type.emoji"
                placeholder="👍"
                :input-attrs="{ required: true, maxlength: 40 }"
                allow-clear
              />
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item
              field="name"
              :label="t('admin.reactionTypes.name')"
              :help="fieldError('name')"
              :validate-status="fieldError('name') ? 'error' : undefined"
            >
              <a-input
                v-model="form.reaction_type.name"
                :placeholder="t('admin.reactionTypes.namePlaceholder')"
                :input-attrs="{ required: true, maxlength: 40 }"
                allow-clear
              />
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item
              field="score"
              :label="t('admin.reactionTypes.score')"
              :help="fieldError('score')"
              :validate-status="fieldError('score') ? 'error' : undefined"
            >
              <a-input-number v-model="form.reaction_type.score" long />
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item
              field="position"
              :label="t('admin.reactionTypes.position')"
              :help="fieldError('position')"
              :validate-status="fieldError('position') ? 'error' : undefined"
            >
              <a-input-number v-model="form.reaction_type.position" :min="0" long />
            </a-form-item>
          </a-grid-item>
        </a-grid>
        <a-form-item
          field="active"
          :label="t('admin.reactionTypes.active')"
          :help="fieldError('active')"
          :validate-status="fieldError('active') ? 'error' : undefined"
        >
          <a-switch
            v-model="form.reaction_type.active"
            :checked-text="t('admin.ui.enabled')"
            :unchecked-text="t('admin.ui.disabled')"
          />
        </a-form-item>
        <a-divider />
        <a-space wrap>
          <a-button
            html-type="submit"
            type="primary"
            shape="round"
            :loading="form.processing"
          >
            {{ t('admin.ui.save') }}
          </a-button>
          <a-button
            v-if="deleteUrl"
            type="primary"
            status="danger"
            :disabled="form.processing"
            @click="destroy"
          >
            {{ t('admin.ui.delete') }}
          </a-button>
        </a-space>
      </a-form>
    </a-card>
  </a-space>
</template>
