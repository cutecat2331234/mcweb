<script setup lang="ts">
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

defineProps<{
  questions: Array<{
    id: number
    product: string
    author: string
    body: string
    status: string
    status_key?: string
    created_at: string
    order_number?: string | null
    hide_url: string
    unhide_url: string
    answers: Array<{
      id: number
      author: string
      body: string
      official: boolean
      status: string
      status_key: string
      hide_url: string
      unhide_url: string
    }>
  }>
}>()

function statusColor(status: string | undefined) {
  if (status === 'published') return 'green'
  if (status === 'hidden') return 'gray'
  if (status === 'pending') return 'orange'
  return 'arcoblue'
}

function hideQuestion(url: string) {
  router.patch(url)
}

function unhideQuestion(url: string) {
  router.patch(url)
}

function hideAnswer(url: string) {
  router.patch(url, {}, { preserveScroll: true })
}

function unhideAnswer(url: string) {
  router.patch(url, {}, { preserveScroll: true })
}
</script>

<template>
  <section class="admin-store-product-questions">
    <a-page-header
      :title="t('admin.productQuestions.title')"
      :show-back="false"
      class="mb-4 !px-0"
    />

    <a-card :bordered="true" :body-style="{ padding: 0 }">
      <a-table
        :data="questions"
        row-key="id"
        :pagination="false"
        :bordered="{ cell: true }"
        :scroll="{ x: 1420 }"
        stripe
      >
        <template #columns>
          <a-table-column
            :title="t('admin.productQuestions.colProduct')"
            data-index="product"
            :width="180"
          />
          <a-table-column
            :title="t('admin.productQuestions.colAuthor')"
            data-index="author"
            :width="150"
          />
          <a-table-column :title="t('admin.productQuestions.colQuestion')" :width="320">
            <template #cell="{ record }">
              <a-tooltip :content="record.body">
                <a-typography-text ellipsis class="block max-w-[290px]">
                  {{ record.body }}
                </a-typography-text>
              </a-tooltip>
            </template>
          </a-table-column>
          <a-table-column :title="t('admin.productQuestions.colOrder')" :width="150">
            <template #cell="{ record }">
              {{ record.order_number || '—' }}
            </template>
          </a-table-column>
          <a-table-column :title="t('admin.productQuestions.colStatus')" :width="130">
            <template #cell="{ record }">
              <a-tag :color="statusColor(record.status_key)">
                {{ record.status }}
              </a-tag>
            </template>
          </a-table-column>
          <a-table-column :title="t('admin.productQuestions.colAnswers')" :width="360">
            <template #cell="{ record }">
              <div v-if="record.answers.length" class="space-y-2">
                <div v-for="answer in record.answers" :key="answer.id" class="rounded border p-2">
                  <div class="flex items-start justify-between gap-2">
                    <div class="min-w-0">
                      <p class="text-xs font-medium">
                        {{ answer.author }}
                        <a-tag v-if="answer.official" size="small" color="arcoblue">{{ t('admin.productQuestions.official') }}</a-tag>
                      </p>
                      <a-typography-text ellipsis class="block max-w-[220px] text-xs">{{ answer.body }}</a-typography-text>
                    </div>
                    <a-button v-if="answer.status_key === 'published'" size="mini" @click="hideAnswer(answer.hide_url)">
                      {{ t('admin.common.hide') }}
                    </a-button>
                    <a-button v-else-if="answer.status_key === 'hidden'" size="mini" @click="unhideAnswer(answer.unhide_url)">
                      {{ t('admin.common.restore') }}
                    </a-button>
                  </div>
                  <a-tag class="mt-1" :color="statusColor(answer.status_key)" size="small">{{ answer.status }}</a-tag>
                </div>
              </div>
              <span v-else class="text-xs text-gray-500">{{ t('admin.productQuestions.noAnswers') }}</span>
            </template>
          </a-table-column>
          <a-table-column
            :title="t('admin.common.time')"
            data-index="created_at"
            :width="180"
          />
          <a-table-column :title="t('admin.ui.actions')" :width="120" fixed="right">
            <template #cell="{ record }">
              <a-button
                v-if="record.status_key === 'published'"
                size="small"
                @click="hideQuestion(record.hide_url)"
              >
                {{ t('admin.common.hide') }}
              </a-button>
              <a-button
                v-else-if="record.status_key === 'hidden'"
                size="small"
                @click="unhideQuestion(record.unhide_url)"
              >
                {{ t('admin.common.restore') }}
              </a-button>
            </template>
          </a-table-column>
        </template>

        <template #empty>
          <a-empty :description="t('admin.productQuestions.empty')" />
        </template>
      </a-table>
    </a-card>
  </section>
</template>
