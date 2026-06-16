<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{ token: string }>()

const form = useForm({
  password_reset: {
    password: '',
    password_confirmation: '',
  },
})

function submit() {
  form.patch(`/app/identity/password_resets/${props.token}`)
}
</script>

<template>
  <PageHeader title="设置新密码" />

  <form class="max-w-md space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="password">新密码</Label>
      <Input id="password" v-model="form.password_reset.password" type="password" required autocomplete="new-password" />
    </div>
    <div class="space-y-2">
      <Label for="password_confirmation">确认密码</Label>
      <Input id="password_confirmation" v-model="form.password_reset.password_confirmation" type="password" required autocomplete="new-password" />
    </div>
    <p v-if="form.errors.base" class="text-sm text-destructive">{{ form.errors.base }}</p>
    <Button type="submit" :disabled="form.processing">更新密码</Button>
    <Link :href="routes.signIn" class="ml-3 text-sm text-muted-foreground hover:text-foreground">返回登录</Link>
  </form>
</template>
