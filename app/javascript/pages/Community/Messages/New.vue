<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import MarkdownEditor from '@/components/portal/MarkdownEditor.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  group?: boolean
  recipient?: string | null
  canSendPm?: boolean
}>()

const form = useForm({
  conversation: {
    is_group: props.group ? '1' : '0',
    recipient: props.recipient || '',
    recipients: '',
    title: '',
    body: '',
  },
})
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '私信', href: routes.forumMessages },
    { label: group ? '新建群组' : '发私信', current: true },
  ]" />

  <div class="mb-4 flex flex-wrap items-center justify-between gap-2">
    <PageHeader :title="group ? '新建群组私信' : '发私信'" />
    <Button v-if="!group" as-child variant="outline" size="sm">
      <Link :href="routes.forumMessagesGroupNew">群组私信</Link>
    </Button>
    <Button v-else as-child variant="outline" size="sm">
      <Link :href="routes.forumMessagesNew">一对一私信</Link>
    </Button>
  </div>

  <p v-if="!group && canSendPm === false" class="mb-4 rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
    新成员（信任等级 0）暂时无法发送私信，多发帖参与社区即可解锁。
  </p>

  <form class="max-w-lg space-y-4" @submit.prevent="form.post(routes.forumMessages)">
    <template v-if="group">
      <div class="space-y-2">
        <Label for="title">群组名称</Label>
        <Input id="title" v-model="form.conversation.title" required placeholder="例如：活动讨论组" />
      </div>
      <div class="space-y-2">
        <Label for="recipients">成员用户名（逗号分隔）</Label>
        <Input id="recipients" v-model="form.conversation.recipients" required placeholder="user1, user2" />
      </div>
    </template>
    <div v-else class="space-y-2">
      <Label for="recipient">收件人用户名</Label>
      <Input id="recipient" v-model="form.conversation.recipient" required placeholder="username" />
    </div>
    <div class="space-y-2">
      <Label>消息内容</Label>
      <MarkdownEditor v-model="form.conversation.body" :show-mention="false" />
    </div>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing || (!group && canSendPm === false)">发送</Button>
      <Button as-child variant="outline">
        <Link :href="routes.forumMessages">取消</Link>
      </Button>
    </div>
  </form>
</template>
