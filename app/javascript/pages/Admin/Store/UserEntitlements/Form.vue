<script setup lang="ts">
import { computed, ref } from 'vue'
import { router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import HighRiskActionModal from '@/components/admin/HighRiskActionModal.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  products: Array<{ id: number; name: string; duration: string }>
  submitUrl: string
  authorizationUrl: string
  backUrl: string
}>()

const form = useForm({
  user_entitlement: {
    username: '',
    product_id: props.products[0]?.id ?? null,
  },
})
const confirmationVisible = ref(false)
const productOptions = computed(() =>
  props.products.map((product) => ({
    value: product.id,
    label: `${product.name} · ${product.duration}`,
  })),
)
const highRiskPayload = computed(() => ({
  user_entitlement: {
    username: form.user_entitlement.username.trim(),
    product_id: form.user_entitlement.product_id,
  },
}))

function fieldError(field: string) {
  return form.errors[field] || form.errors[`user_entitlement.${field}`]
}

function submit(event?: { errors?: unknown }) {
  if (event?.errors) return
  confirmationVisible.value = true
}

function completed(result: Record<string, unknown>) {
  const redirectUrl = result.redirect_url
  if (typeof redirectUrl === 'string' && redirectUrl.length > 0) {
    router.visit(redirectUrl)
  }
}
</script>

<template>
  <a-space direction="vertical" size="large" fill>
    <a-page-header :title="title" :show-back="false" />

    <a-grid :cols="24" :col-gap="16" :row-gap="16">
      <a-grid-item :span="{ xs: 24, md: 18, lg: 14, xl: 12 }">
        <a-card :bordered="true">
          <a-space direction="vertical" size="large" fill>
            <a-alert
              type="warning"
              show-icon
              :title="t('admin.highRisk.warningTitle')"
            >
              {{ t('admin.forms.userEntitlement.grantHint') }}
            </a-alert>

            <a-form :model="form.user_entitlement" layout="vertical" @submit="submit">
              <a-form-item
                field="username"
                :label="t('admin.forms.userEntitlement.username')"
                :rules="[{ required: true, message: t('admin.forms.userEntitlement.username') }]"
                :validate-status="fieldError('username') ? 'error' : undefined"
                :help="fieldError('username')"
              >
                <a-input v-model="form.user_entitlement.username" allow-clear />
              </a-form-item>

              <a-form-item
                field="product_id"
                :label="t('admin.forms.userEntitlement.product')"
                :validate-status="fieldError('product_id') ? 'error' : undefined"
                :help="fieldError('product_id')"
              >
                <a-select
                  v-model="form.user_entitlement.product_id"
                  :options="productOptions"
                  allow-search
                />
              </a-form-item>

              <a-space wrap>
                <a-button
                  type="primary"
                  html-type="submit"
                  :disabled="!form.user_entitlement.username.trim() || !form.user_entitlement.product_id"
                >
                  {{ t('admin.forms.userEntitlement.grant') }}
                </a-button>
                <a-button @click="router.visit(backUrl)">
                  {{ t('admin.ui.cancel') }}
                </a-button>
              </a-space>
            </a-form>
          </a-space>
        </a-card>
      </a-grid-item>
    </a-grid>

    <HighRiskActionModal
      v-model:visible="confirmationVisible"
      :title="t('admin.forms.userEntitlement.grantReviewTitle')"
      :authorization-url="authorizationUrl"
      :action-url="submitUrl"
      :payload="highRiskPayload"
      @completed="completed"
    />
  </a-space>
</template>
