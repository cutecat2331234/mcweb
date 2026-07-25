<script setup lang="ts">
import { computed } from 'vue'
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { confirm } from '@/lib/arcoConfirm'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  email_ban: { pattern: string; reason: string; expires_at: string | null }
  errors?: Record<string, string>
  submitUrl: string
  method?: 'post' | 'patch'
  backUrl: string
  deleteUrl?: string | null
}>()

const form = useForm({ email_ban: { ...props.email_ban } })

const expiresAt = computed<string | undefined>({
  get: () => form.email_ban.expires_at || undefined,
  set: (value) => {
    form.email_ban.expires_at = value || null
  },
})

function fieldError(field: string) {
  return props.errors?.[field]
    || form.errors[field]
    || form.errors[`email_ban.${field}`]
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
    title: t('admin.emailBansForm.deleteTitle'),
    message: t('admin.emailBansForm.deleteConfirm'),
    confirmLabel: t('admin.ui.delete'),
    variant: 'destructive',
  })
  if (!props.deleteUrl || !ok) return
  form.delete(props.deleteUrl)
}
</script>

<template>
  <section class="admin-system-email-ban-form">
    <a-page-header :title="title" :show-back="false" class="mb-4 !px-0" />

    <a-card class="max-w-2xl" :bordered="true">
      <a-form :model="form.email_ban" layout="vertical" @submit="submit">
        <a-form-item
          field="pattern"
          :label="t('admin.emailBansForm.pattern')"
          :rules="[{ required: true, message: t('admin.emailBansForm.pattern') }]"
          :validate-status="fieldError('pattern') ? 'error' : undefined"
          :help="fieldError('pattern') || t('admin.emailBansForm.patternHint')"
        >
          <a-input
            v-model="form.email_ban.pattern"
            placeholder="*@spam.com"
            allow-clear
          />
        </a-form-item>

        <a-form-item
          field="reason"
          :label="t('admin.emailBansForm.reason')"
          :validate-status="fieldError('reason') ? 'error' : undefined"
          :help="fieldError('reason')"
        >
          <a-textarea
            v-model="form.email_ban.reason"
            :auto-size="{ minRows: 2, maxRows: 6 }"
            allow-clear
          />
        </a-form-item>

        <a-form-item
          field="expires_at"
          :label="t('admin.emailBansForm.expiresAt')"
          :validate-status="fieldError('expires_at') ? 'error' : undefined"
          :help="fieldError('expires_at') || t('admin.emailBansForm.expiresHint')"
        >
          <a-date-picker
            v-model="expiresAt"
            class="w-full"
            show-time
            format="YYYY-MM-DD HH:mm"
            value-format="YYYY-MM-DDTHH:mm"
            allow-clear
          />
        </a-form-item>

        <a-space wrap>
          <a-button
            type="primary"
            html-type="submit"
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
          <Link
            :href="backUrl"
            class="arco-btn arco-btn-outline arco-btn-size-medium no-underline"
          >
            {{ t('admin.ui.back') }}
          </Link>
        </a-space>
      </a-form>
    </a-card>
  </section>
</template>
