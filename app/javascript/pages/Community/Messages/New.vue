<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { Link, useForm } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Alert from '@/components/ui/Alert.vue'
import MarkdownEditor from '@/components/portal/MarkdownEditor.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  group?: boolean
  recipient?: string | null
  recipients?: string | null
  title?: string | null
  initialBody?: string | null
  canSendPm?: boolean
  warningRestrictions?: { post?: string | null; link?: string | null; pm?: string | null }
  form_errors?: Record<string, string>
}>()

const pmBlocked = computed(() => !!props.warningRestrictions?.pm)
const linkError = ref('')

function containsLink(text: string) {
  return /https?:\/\/|www\./i.test(text)
}

const form = useForm({
  conversation: {
    is_group: props.group ? '1' : '0',
    recipient: props.recipient || '',
    recipients: props.recipients || '',
    title: props.title || '',
    body: props.initialBody || '',
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
  return form.errors[`conversation.${key}` as keyof typeof form.errors] || props.form_errors?.[`conversation.${key}`] || ''
}

const bodyHasBlockedLink = computed(() =>
  !!(props.warningRestrictions?.link && containsLink(form.conversation.body))
)

const canSend = computed(() =>
  !pmBlocked.value &&
  props.canSendPm !== false &&
  !bodyHasBlockedLink.value
)

function submitMessage() {
  linkError.value = ''
  if (pmBlocked.value) return
  if (props.warningRestrictions?.link && containsLink(form.conversation.body)) {
    linkError.value = props.warningRestrictions.link
    return
  }
  form.post(routes.forumMessages)
}
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

  <p v-if="canSendPm === false" class="mb-4 rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
    新成员（信任等级 0）暂时无法发送私信，多发帖参与社区即可解锁。
  </p>

  <p v-if="pmBlocked" class="mb-4 rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-100">
    {{ warningRestrictions?.pm }}
  </p>

  <p v-if="group && warningRestrictions?.link" class="mb-4 max-w-lg rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-100">
    {{ warningRestrictions.link }}
  </p>

  <Alert v-if="formError" variant="destructive" class="mb-4 max-w-lg">
    {{ formError }}
  </Alert>

  <form class="max-w-lg space-y-4" @submit.prevent="submitMessage">
    <template v-if="group">
      <div class="space-y-2">
        <Label for="title">群组名称</Label>
        <Input id="title" v-model="form.conversation.title" required placeholder="例如：活动讨论组" />
        <p v-if="fieldError('title')" class="text-sm text-destructive">{{ fieldError('title') }}</p>
      </div>
      <div class="space-y-2">
        <Label for="recipients">成员用户名（逗号分隔）</Label>
        <Input id="recipients" v-model="form.conversation.recipients" required placeholder="user1, user2" />
        <p v-if="fieldError('recipients')" class="text-sm text-destructive">{{ fieldError('recipients') }}</p>
      </div>
    </template>
    <div v-else class="space-y-2">
      <Label for="recipient">收件人用户名</Label>
      <Input id="recipient" v-model="form.conversation.recipient" required placeholder="username" />
      <p v-if="fieldError('recipient')" class="text-sm text-destructive">{{ fieldError('recipient') }}</p>
    </div>
    <div class="space-y-2">
      <Label>消息内容</Label>
      <MarkdownEditor v-model="form.conversation.body" :show-mention="false" />
      <p v-if="fieldError('body')" class="text-sm text-destructive">{{ fieldError('body') }}</p>
      <p v-else-if="linkError" class="text-sm text-destructive">{{ linkError }}</p>
      <p v-else-if="bodyHasBlockedLink" class="text-sm text-destructive">{{ warningRestrictions?.link }}</p>
      <p v-else-if="warningRestrictions?.link" class="text-xs text-muted-foreground">{{ warningRestrictions.link }}</p>
    </div>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing || !canSend">发送</Button>
      <Button as-child variant="outline">
        <Link :href="routes.forumMessages">取消</Link>
      </Button>
    </div>
  </form>
</template>
