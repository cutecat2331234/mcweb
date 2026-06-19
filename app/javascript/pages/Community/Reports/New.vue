<script setup lang="ts">
import { computed, watch } from 'vue'
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Textarea from '@/components/ui/Textarea.vue'
import Label from '@/components/ui/Label.vue'
import Select from '@/components/ui/Select.vue'
import Alert from '@/components/ui/Alert.vue'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

const props = defineProps<{
  reportableType: string
  reportableId: string
  reasonOptions: Array<{ value: string; label: string }>
  form_errors?: Record<string, string>
}>()

const form = useForm({
  report: {
    reportable_type: props.reportableType,
    reportable_id: props.reportableId,
    reason_code: 'spam',
    reason_detail: '',
  },
})

watch(
  () => props.form_errors,
  (errors) => {
    if (!errors) return
    Object.entries(errors).forEach(([key, message]) => {
      form.setError(key as keyof typeof form.errors, message)
    })
  },
  { immediate: true },
)

const formError = computed(() => {
  if (form.errors.base) return form.errors.base
  return props.form_errors?.base || ''
})

function fieldError(key: string) {
  return form.errors[`report.${key}` as keyof typeof form.errors] || props.form_errors?.[`report.${key}`] || ''
}

function submit() {
  form.post('/app/forum/reports')
}
</script>

<template>
  <PageHeader :title="t('forum.reports.title')" />

  <Alert v-if="formError" variant="destructive" class="mb-4 max-w-lg">
    {{ formError }}
  </Alert>

  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="reason_code">{{ t('forum.reports.reasonType') }}</Label>
      <Select id="reason_code" v-model="form.report.reason_code" :options="reasonOptions" block />
    </div>
    <div class="space-y-2">
      <Label for="reason_detail">{{ t('forum.reports.reasonDetail') }}</Label>
      <Textarea id="reason_detail" v-model="form.report.reason_detail" rows="4" :placeholder="t('forum.reports.reasonPlaceholder')" />
      <p v-if="fieldError('reason')" class="text-sm text-destructive">{{ fieldError('reason') }}</p>
      <p v-else-if="fieldError('reason_detail')" class="text-sm text-destructive">{{ fieldError('reason_detail') }}</p>
    </div>
    <div class="flex gap-3">
      <Button type="submit" :disabled="form.processing">{{ t('forum.reports.submit') }}</Button>
      <Button as-child variant="outline">
        <Link href="/" preserve-state>{{ t('forum.reports.cancel') }}</Link>
      </Button>
    </div>
  </form>
</template>
