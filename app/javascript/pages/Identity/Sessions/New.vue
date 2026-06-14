<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

defineProps<{
  errors?: Record<string, string>
}>()

const form = useForm({
  email: '',
  password: '',
  totp_code: '',
  remember_me: false,
})

function submit() {
  form.post('/identity/session', {
    preserveScroll: true,
  })
}
</script>

<template>
  <PageHeader title="登录" subtitle="访问你的 Mcweb 账户" />

  <form class="max-w-md space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="email">邮箱</Label>
      <Input id="email" v-model="form.email" type="email" autocomplete="email" required autofocus />
      <p v-if="form.errors.email" class="text-sm text-destructive">{{ form.errors.email }}</p>
    </div>

    <div class="space-y-2">
      <Label for="password">密码</Label>
      <Input id="password" v-model="form.password" type="password" autocomplete="current-password" required />
      <p v-if="form.errors.password" class="text-sm text-destructive">{{ form.errors.password }}</p>
    </div>

    <div class="space-y-2">
      <Label for="totp_code">两步验证码（如已启用）</Label>
      <Input id="totp_code" v-model="form.totp_code" autocomplete="one-time-code" />
    </div>

    <label class="flex items-center gap-2 text-sm">
      <input v-model="form.remember_me" type="checkbox" class="rounded border-input">
      记住我
    </label>

    <p v-if="form.errors.base" class="text-sm text-destructive">{{ form.errors.base }}</p>

    <div class="flex items-center gap-3 pt-2">
      <Button type="submit" :disabled="form.processing">登录</Button>
      <Link :href="routes.register" class="text-sm text-muted-foreground hover:text-foreground">
        创建账户
      </Link>
    </div>
  </form>
</template>
