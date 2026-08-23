<script setup lang="ts">
import { router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { confirm } from '@/lib/arcoConfirm'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  theme: { name: string; key: string; tokens_json: string }
  submitUrl: string
  deleteUrl?: string | null
  method: 'post' | 'patch'
  backUrl: string
  form_errors?: Record<string, string[]>
}>()

const form = useForm({ theme: { ...props.theme } })

function fieldError(key: string) {
  return props.form_errors?.[key]?.join(' ') || ''
}

function submit() {
  if (props.method === 'patch') form.patch(props.submitUrl)
  else form.post(props.submitUrl)
}

async function destroy() {
  const ok = await confirm({
    title: t('admin.ui.delete'),
    message: t('admin.website.nav.deleteConfirm', { label: props.theme.name }),
    confirmLabel: t('admin.ui.delete'),
    cancelLabel: t('admin.ui.cancel'),
    variant: 'destructive',
  })
  if (!props.deleteUrl || !ok) return
  form.delete(props.deleteUrl)
}
</script>

<template>
  <a-space direction="vertical" :size="24" fill>
    <a-page-header :title="title" :show-back="false" />

    <a-row justify="center">
      <a-col :xs="24" :md="22" :lg="20" :xl="18">
        <a-card :bordered="true">
          <a-form :model="form.theme" layout="vertical" @submit="submit">
            <a-row :gutter="[16, 0]">
              <a-col :xs="24" :md="12">
                <a-form-item
                  field="name"
                  :label="t('admin.website.themes.name')"
                  required
                  :validate-status="fieldError('name') ? 'error' : undefined"
                  :help="fieldError('name')"
                >
                  <a-input v-model="form.theme.name" allow-clear />
                </a-form-item>
              </a-col>
              <a-col :xs="24" :md="12">
                <a-form-item
                  field="key"
                  :label="t('admin.website.themes.key')"
                  required
                  :validate-status="fieldError('key') ? 'error' : undefined"
                  :help="fieldError('key')"
                >
                  <a-input v-model="form.theme.key" allow-clear />
                </a-form-item>
              </a-col>
            </a-row>

            <a-form-item
              field="tokens_json"
              :label="t('admin.website.themes.tokensJson')"
              :validate-status="fieldError('tokens_json') ? 'error' : undefined"
              :help="fieldError('tokens_json')"
            >
              <a-textarea
                v-model="form.theme.tokens_json"
                :auto-size="{ minRows: 8, maxRows: 18 }"
              />
            </a-form-item>

            <a-divider />

            <a-space wrap>
              <a-button
                html-type="submit"
                type="primary"
                :loading="form.processing"
              >
                {{ t('admin.ui.save') }}
              </a-button>
              <a-button v-if="deleteUrl" html-type="button" status="danger" @click="destroy">
                {{ t('admin.ui.delete') }}
              </a-button>
              <a-button html-type="button" @click="router.visit(backUrl)">
                {{ t('admin.ui.cancel') }}
              </a-button>
            </a-space>
          </a-form>
        </a-card>
      </a-col>
    </a-row>
  </a-space>
</template>
