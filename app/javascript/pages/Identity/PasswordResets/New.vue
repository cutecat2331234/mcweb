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
  password_reset: { email: '' },
})

function submit() {
  form.post('/app/identity/password_resets')
}
</script>

<template>
  <PageHeader title="重置密码" />

  <form class="max-w-md space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="email">邮箱</Label>
      <Input id="email" v-model="form.password_reset.email" type="email" required autofocus />
    </div>
    <div class="flex gap-3">
      <Button type="submit" :disabled="form.processing">发送重置链接</Button>
      <Link :href="routes.signIn" class="text-sm text-muted-foreground hover:text-foreground">返回登录</Link>
    </div>
  </form>
</template>
