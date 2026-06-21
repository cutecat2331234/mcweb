<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
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
  email?: string
}>()

const { t } = useI18n()

const form = useForm({
  resend: {
    email: props.email || '',
  },
})

function submit() {
  form.post(routes.resendVerification)
}
</script>

<template>
  <PageHeader :title="t('identity.resendVerification.title')" :subtitle="t('identity.resendVerification.subtitle')" />

  <Alert class="mb-4 max-w-md">
    {{ t('identity.resendVerification.hint') }}
  </Alert>

  <form class="max-w-md space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="email">{{ t('auth.register.email') }}</Label>
      <Input id="email" v-model="form.resend.email" type="email" required autocomplete="email" />
    </div>
    <div class="flex flex-wrap items-center gap-3">
      <Button type="submit" :disabled="form.processing">{{ t('identity.resendVerification.submit') }}</Button>
      <Link :href="routes.signIn" class="text-sm text-muted-foreground hover:text-foreground">
        {{ t('auth.register.hasAccount') }}
      </Link>
    </div>
  </form>
</template>
