<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Textarea from '@/components/ui/Textarea.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  recipient?: string | null
}>()

const form = useForm({
  conversation: {
    recipient: props.recipient || '',
    body: '',
  },
})

function submit() {
  form.post(routes.forumMessages)
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '私信', href: routes.forumMessages },
    { label: '发私信', current: true },
  ]" />

  <PageHeader title="发私信" />

  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="recipient">收件人用户名</Label>
      <Input id="recipient" v-model="form.conversation.recipient" required placeholder="username" />
    </div>
    <div class="space-y-2">
      <Label for="body">消息内容</Label>
      <Textarea id="body" v-model="form.conversation.body" required rows="6" />
    </div>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">发送</Button>
      <Button as-child variant="outline">
        <Link :href="routes.forumMessages">取消</Link>
      </Button>
    </div>
  </form>
</template>
