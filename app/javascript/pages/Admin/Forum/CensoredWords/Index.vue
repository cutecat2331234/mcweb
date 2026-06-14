<script setup lang="ts">
import { useForm } from '@inertiajs/vue3'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import { Link } from '@inertiajs/vue3'

defineOptions({ layout: AdminLayout })

const props = defineProps<{
  words: Array<{ id: number; word: string; replacement: string; destroy_url: string }>
  createUrl: string
}>()

const form = useForm({
  censored_word: { word: '', replacement: '***' },
})

function submit() {
  form.post(props.createUrl, {
    preserveScroll: true,
    onSuccess: () => form.reset(),
  })
}
</script>

<template>
  <PageHeader title="敏感词过滤" subtitle="发帖内容将自动替换匹配的词语" />

  <form class="mb-6 max-w-md space-y-3 rounded-lg border p-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="word">敏感词</Label>
      <Input id="word" v-model="form.censored_word.word" required />
    </div>
    <div class="space-y-2">
      <Label for="replacement">替换为</Label>
      <Input id="replacement" v-model="form.censored_word.replacement" required />
    </div>
    <Button type="submit" size="sm" :disabled="form.processing">添加</Button>
  </form>

  <ul v-if="words.length" class="max-w-md space-y-2 rounded-lg border p-4 text-sm">
    <li v-for="word in words" :key="word.id" class="flex items-center justify-between gap-3">
      <span><strong>{{ word.word }}</strong> → {{ word.replacement }}</span>
      <Link :href="word.destroy_url" method="delete" as="button" class="text-xs text-destructive hover:underline">删除</Link>
    </li>
  </ul>
  <p v-else class="text-sm text-muted-foreground">暂无敏感词。</p>
</template>
