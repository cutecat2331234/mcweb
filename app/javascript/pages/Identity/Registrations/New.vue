<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

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

function submit() {
  form.post('/app/identity/register')
}
</script>

<template>
  <PageHeader title="创建账户" subtitle="加入 Mcweb 社区" />

  <form class="max-w-md space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="email">邮箱</Label>
      <Input id="email" v-model="form.registration.email" type="email" required autofocus autocomplete="email" />
    </div>
    <div class="space-y-2">
      <Label for="username">用户名</Label>
      <Input id="username" v-model="form.registration.username" required autocomplete="username" />
    </div>
    <div class="space-y-2">
      <Label for="display_name">显示名称</Label>
      <Input id="display_name" v-model="form.registration.display_name" autocomplete="name" />
    </div>
    <div class="space-y-2">
      <Label for="password">密码</Label>
      <Input id="password" v-model="form.registration.password" type="password" required autocomplete="new-password" />
    </div>
    <p v-if="form.errors.base" class="text-sm text-destructive">{{ form.errors.base }}</p>
    <div class="flex gap-3 pt-2">
      <Button type="submit" :disabled="form.processing">注册</Button>
      <Link :href="routes.signIn" class="text-sm text-muted-foreground hover:text-foreground">已有账户？登录</Link>
    </div>
  </form>
</template>
