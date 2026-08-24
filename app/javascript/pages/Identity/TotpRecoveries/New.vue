<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import IdentityDocumentLayout from '@/layouts/account/IdentityDocumentLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Alert from '@/components/ui/Alert.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: IdentityDocumentLayout })

const { t } = useI18n()
const form = useForm({
  totp_recovery: {
    email: '',
  },
})

function submit() {
  form.post(routes.totpRecovery)
}
</script>

<template>
  <PageHeader
    density="compact"
    :title="t('identity.totpRecovery.requestTitle')"
    :subtitle="t('identity.totpRecovery.requestSubtitle')"
  />

  <div class="w-full space-y-5">
    <Alert :title="t('identity.totpRecovery.securityTitle')">
      {{ t('identity.totpRecovery.securityHint') }}
    </Alert>

    <form class="space-y-4" @submit.prevent="submit">
      <div class="space-y-2">
        <Label for="totp_recovery_email">{{ t('auth.signIn.email') }}</Label>
        <Input
          id="totp_recovery_email"
          v-model="form.totp_recovery.email"
          type="email"
          autocomplete="email"
          density="comfortable"
          required
        />
      </div>
      <div class="flex flex-col items-stretch gap-4 sm:flex-row sm:items-center">
        <Button class="w-full sm:w-auto" size="comfortable" type="submit" :disabled="form.processing">
          {{ t('identity.totpRecovery.send') }}
        </Button>
        <Link :href="routes.signIn" class="text-sm text-muted-foreground hover:text-foreground">
          {{ t('auth.passwordReset.backToSignIn') }}
        </Link>
      </div>
    </form>
  </div>
</template>
