<script setup lang="ts">
import { computed, watch } from 'vue'
import { Link, useForm } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Alert from '@/components/ui/Alert.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  token: string
  form_errors?: Record<string, string>
}>()

const form = useForm({
  password_reset: {
    password: '',
    password_confirmation: '',
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

const formError = computed(() => form.errors.base || props.form_errors?.base || '')

function submit() {
  form.patch(`/app/identity/password_resets/${props.token}`)
}
</script>

<template>
  <PageHeader title="设置新密码" />

  <Alert v-if="formError" variant="destructive" title="无法更新密码" class="mb-4 max-w-md">
    {{ formError }}
  </Alert>

  <form class="max-w-md space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="password">新密码</Label>
      <Input id="password" v-model="form.password_reset.password" type="password" required autocomplete="new-password" />
    </div>
    <div class="space-y-2">
      <Label for="password_confirmation">确认密码</Label>
      <Input id="password_confirmation" v-model="form.password_reset.password_confirmation" type="password" required autocomplete="new-password" />
    </div>
    <div class="flex flex-wrap items-center gap-3">
      <Button type="submit" :disabled="form.processing">更新密码</Button>
      <Link :href="routes.signIn" class="text-sm text-muted-foreground hover:text-foreground">返回登录</Link>
    </div>
  </form>
</template>
