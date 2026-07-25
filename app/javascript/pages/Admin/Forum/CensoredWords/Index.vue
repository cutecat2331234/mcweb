<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

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
  <a-page-header
    :title="t('admin.censoredWords.title')"
    :subtitle="t('admin.censoredWords.subtitle')"
    :show-back="false"
    class="mb-4 !px-0"
  />

  <a-card class="mb-6 max-w-xl" :bordered="true">
    <form class="grid gap-4" @submit.prevent="submit">
      <label class="admin-forum-field">
        <span>{{ t('admin.censoredWords.word') }}</span>
        <a-input v-model="form.censored_word.word" :input-attrs="{ required: true }" allow-clear />
      </label>
      <label class="admin-forum-field">
        <span>{{ t('admin.common.replacement') }}</span>
        <a-input v-model="form.censored_word.replacement" :input-attrs="{ required: true }" allow-clear />
      </label>
      <div>
        <a-button html-type="submit" type="primary" size="small" :loading="form.processing">
          {{ t('admin.common.add') }}
        </a-button>
      </div>
    </form>
  </a-card>

  <a-card class="max-w-xl" :bordered="true">
    <a-list v-if="words.length" :bordered="false">
      <a-list-item v-for="word in words" :key="word.id">
        <div class="flex w-full items-center justify-between gap-3">
          <span><strong>{{ word.word }}</strong> → {{ word.replacement }}</span>
          <Link
            :href="word.destroy_url"
            method="delete"
            as="button"
            class="arco-btn arco-btn-text arco-btn-size-small arco-btn-status-danger"
          >
            {{ t('admin.ui.delete') }}
          </Link>
        </div>
      </a-list-item>
    </a-list>
    <a-empty v-else :description="t('admin.censoredWords.empty')" />
  </a-card>
</template>

<style scoped>
.admin-forum-field {
  display: grid;
  gap: 6px;
  color: var(--color-text-2);
  font-size: 14px;
}
</style>
