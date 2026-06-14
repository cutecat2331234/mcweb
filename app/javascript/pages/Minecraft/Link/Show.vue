<script setup lang="ts">
import { useForm } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const form = useForm({
  link: { code: '' },
})

function submit() {
  form.post(routes.minecraftLink)
}
</script>

<template>
  <PageHeader title="绑定 Minecraft 账户" subtitle="在游戏内执行 /website link，然后输入验证码" />

  <form class="max-w-sm space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="code">验证码</Label>
      <Input id="code" v-model="form.link.code" class="font-mono" required autocomplete="off" />
      <p v-if="form.errors.base" class="text-sm text-destructive">{{ form.errors.base }}</p>
    </div>
    <Button type="submit" :disabled="form.processing">绑定账户</Button>
  </form>
</template>
