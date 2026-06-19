<script setup lang="ts">
import { computed } from 'vue'
import { Link, useForm, usePage } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Alert from '@/components/ui/Alert.vue'
import { routes } from '@/lib/routes'
import { csrfHeaders, readCsrfToken } from '@/lib/csrf'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  form_error?: string
}>()

const page = usePage()

const form = useForm({
  password_reset: { email: '' },
})

const formError = computed(() => {
  if (form.errors.base) return form.errors.base
  if (props.form_error) return props.form_error
  const pageErrors = page.props.errors as Record<string, string> | undefined
  return pageErrors?.base || ''
})

function submit() {
  const token = String(page.props.csrf_token || readCsrfToken())
  form
    .transform((data) => ({ ...data, authenticity_token: token }))
    .post(routes.identityPasswordResets, {
      preserveScroll: true,
      headers: csrfHeaders(),
    })
}
</script>

<template>
  <PageHeader title="重置密码" subtitle="输入注册邮箱，我们将发送重置链接" />

  <Alert v-if="formError" variant="destructive" title="无法发送" class="mb-4 max-w-md">
    {{ formError }}
  </Alert>

  <form class="max-w-md space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="email">邮箱</Label>
      <Input id="email" v-model="form.password_reset.email" type="email" required autofocus />
    </div>
    <div class="flex flex-wrap items-center justify-between gap-3">
      <Button type="submit" :disabled="form.processing">发送重置链接</Button>
      <Link :href="routes.signIn" class="text-sm text-muted-foreground hover:text-foreground">返回登录</Link>
    </div>
  </form>
</template>
