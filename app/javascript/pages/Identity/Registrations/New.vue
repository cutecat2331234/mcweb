<script setup lang="ts">
import { computed, watch } from 'vue'
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
  form_errors?: Record<string, string>
}>()

const page = usePage()

const form = useForm({
  registration: {
    email: '',
    username: '',
    display_name: '',
    password: '',
    locale: 'zh-CN',
    time_zone: 'Asia/Shanghai',
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
  return form.errors[`registration.${key}` as keyof typeof form.errors] || props.form_errors?.[`registration.${key}`] || ''
}

function submit() {
  const token = String(page.props.csrf_token || readCsrfToken())
  form
    .transform((data) => ({ ...data, authenticity_token: token }))
    .post(routes.register, {
      preserveScroll: true,
      headers: csrfHeaders(),
    })
}
</script>

<template>
  <PageHeader title="创建账户" subtitle="加入 Mcweb 社区" />

  <Alert v-if="formError" variant="destructive" title="注册失败" class="mb-4 max-w-md">
    {{ formError }}
  </Alert>

  <form class="max-w-md space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="email">邮箱</Label>
      <Input id="email" v-model="form.registration.email" type="email" required autofocus autocomplete="email" />
      <p v-if="fieldError('email')" class="text-sm text-destructive">{{ fieldError('email') }}</p>
    </div>
    <div class="space-y-2">
      <Label for="username">用户名</Label>
      <Input id="username" v-model="form.registration.username" required autocomplete="username" />
      <p v-if="fieldError('username')" class="text-sm text-destructive">{{ fieldError('username') }}</p>
    </div>
    <div class="space-y-2">
      <Label for="display_name">显示名称</Label>
      <Input id="display_name" v-model="form.registration.display_name" autocomplete="name" />
    </div>
    <div class="space-y-2">
      <Label for="password">密码</Label>
      <Input id="password" v-model="form.registration.password" type="password" required autocomplete="new-password" />
      <p v-if="fieldError('password')" class="text-sm text-destructive">{{ fieldError('password') }}</p>
    </div>
    <div class="flex flex-wrap items-center justify-between gap-3 pt-2">
      <Button type="submit" :disabled="form.processing">注册</Button>
      <Link :href="routes.signIn" class="text-sm text-muted-foreground hover:text-foreground">已有账户？登录</Link>
    </div>
  </form>
</template>
