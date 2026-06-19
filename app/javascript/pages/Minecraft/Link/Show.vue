<script setup lang="ts">
import { computed, watch } from 'vue'
import { useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Alert from '@/components/ui/Alert.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  form_error?: string | null
}>()

const { t } = useI18n()

const form = useForm({
  link: { code: '' },
})

watch(
  () => props.form_error,
  (message) => {
    if (!message) return
    form.setError('base', message)
  },
  { immediate: true },
)

const formError = computed(() => form.errors.base || props.form_error || '')

function submit() {
  form.post(routes.minecraftLink)
}
</script>

<template>
  <PageHeader :title="t('minecraft.link.title')" :subtitle="t('minecraft.link.subtitle')" />

  <Alert v-if="formError" variant="destructive" class="mb-4 max-w-sm">
    {{ formError }}
  </Alert>

  <form class="max-w-sm space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="code">{{ t('minecraft.link.code') }}</Label>
      <Input id="code" v-model="form.link.code" class="font-mono" required autocomplete="off" />
      <p v-if="form.errors['link.code']" class="text-sm text-destructive">{{ form.errors['link.code'] }}</p>
    </div>
    <Button type="submit" :disabled="form.processing">{{ t('minecraft.link.submit') }}</Button>
  </form>
</template>
