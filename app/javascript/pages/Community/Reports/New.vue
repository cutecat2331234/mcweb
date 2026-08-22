<script setup lang="ts">
import { computed, watch } from 'vue'
import { Head, Link, router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Alert,
  Breadcrumb,
  BreadcrumbItem,
  Button,
  Card,
  Form,
  FormItem,
  PageHeader,
  Select,
  Space,
  Textarea,
} from '@mcweb/ui'
import PortalLayout from '@/layouts/PortalLayout.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

const props = defineProps<{
  reportableType: string
  reportableId: string
  reasonOptions: Array<{ value: string; label: string }>
  formAction: string
  indexUrl: string
  form_errors?: Record<string, string> | null
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
    form.clearErrors()
    if (!errors) return
    Object.entries(errors).forEach(([key, message]) => {
      form.setError(key as keyof typeof form.errors, message)
    })
  },
  { immediate: true },
)

const formError = computed(() => form.errors.base || props.form_errors?.base || '')

function fieldError(key: string) {
  return form.errors[`report.${key}` as keyof typeof form.errors]
    || props.form_errors?.[`report.${key}`]
    || ''
}

function submit() {
  form.post(props.formAction)
}
</script>

<template>
  <Head :title="t('forum.reports.title')">
    <meta name="robots" content="noindex,nofollow">
  </Head>

  <Space direction="vertical" fill size="large">
    <PageHeader
      :title="t('forum.reports.title')"
      :subtitle="t('forum.reports.newSubtitle')"
      :show-back="false"
    >
      <template #breadcrumb>
        <Breadcrumb>
          <BreadcrumbItem><Link :href="routes.forum">{{ t('breadcrumb.forum') }}</Link></BreadcrumbItem>
          <BreadcrumbItem><Link :href="indexUrl">{{ t('forum.reports.caseCenter') }}</Link></BreadcrumbItem>
          <BreadcrumbItem>{{ t('forum.reports.newCase') }}</BreadcrumbItem>
        </Breadcrumb>
      </template>
    </PageHeader>

    <Alert v-if="formError" type="error" show-icon aria-live="polite">
      {{ formError }}
    </Alert>

    <Card :title="t('forum.reports.newCase')" :bordered="true">
      <Form :model="form.report" layout="vertical" @submit="submit">
        <FormItem
          field="reason_code"
          :label="t('forum.reports.reasonType')"
          required
        >
          <Select v-model="form.report.reason_code" :options="reasonOptions" />
        </FormItem>
        <FormItem
          field="reason_detail"
          :label="t('forum.reports.reasonDetail')"
          :help="fieldError('reason') || fieldError('reason_detail')"
          :validate-status="fieldError('reason') || fieldError('reason_detail') ? 'error' : undefined"
        >
          <Textarea
            v-model="form.report.reason_detail"
            :max-length="2000"
            :placeholder="t('forum.reports.reasonPlaceholder')"
            show-word-limit
          />
        </FormItem>
        <Space wrap>
          <Button
            type="primary"
            html-type="submit"
            :loading="form.processing"
            :disabled="form.processing"
          >
            {{ t('forum.reports.submit') }}
          </Button>
          <Button type="secondary" html-type="button" @click="router.visit(indexUrl)">
            {{ t('forum.reports.caseCenter') }}
          </Button>
          <Button type="text" html-type="button" @click="router.visit(routes.forum)">
            {{ t('forum.reports.cancel') }}
          </Button>
        </Space>
      </Form>
    </Card>
  </Space>
</template>
