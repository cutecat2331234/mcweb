<script setup lang="ts">
import { Link, router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Alert from '@/components/ui/Alert.vue'
import Badge from '@/components/ui/Badge.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  email_verified: boolean
  totp_enabled: boolean
  require_totp: boolean
  recovery_codes_remaining: number
  pending_totp?: {
    secret: string
    provisioning_uri: string
    qr_svg: string
  } | null
}>()

const { t } = useI18n()

const confirmForm = useForm({
  totp: { code: '' },
})

const disableForm = useForm({
  totp: { password: '', code: '' },
})

function startSetup() {
  router.post(routes.securityTotpSetup)
}

function confirmTotp() {
  confirmForm.post(routes.securityTotpConfirm)
}

function disableTotp() {
  disableForm.post(routes.securityTotpDisable)
}
</script>

<template>
  <PageHeader :title="t('identity.security.title')" :subtitle="t('identity.security.subtitle')" />

  <div class="max-w-2xl space-y-6">
    <section class="rounded-lg border p-4">
      <div class="flex items-center justify-between gap-3">
        <div>
          <h2 class="font-medium">{{ t('identity.security.emailTitle') }}</h2>
          <p class="mt-1 text-sm text-muted-foreground">{{ t('identity.security.emailHint') }}</p>
        </div>
        <Badge :variant="email_verified ? 'success' : 'secondary'">
          {{ email_verified ? t('identity.security.verified') : t('identity.security.unverified') }}
        </Badge>
      </div>
      <div v-if="!email_verified" class="mt-3">
        <Button as-child variant="outline" size="sm">
          <Link :href="routes.resendVerification">{{ t('identity.resendVerification.submit') }}</Link>
        </Button>
      </div>
    </section>

    <section class="rounded-lg border p-4 space-y-4">
      <div class="flex items-center justify-between gap-3">
        <div>
          <h2 class="font-medium">{{ t('identity.security.totpTitle') }}</h2>
          <p class="mt-1 text-sm text-muted-foreground">{{ t('identity.security.totpHint') }}</p>
        </div>
        <Badge :variant="totp_enabled ? 'success' : 'secondary'">
          {{ totp_enabled ? t('identity.security.enabled') : t('identity.security.disabled') }}
        </Badge>
      </div>

      <Alert v-if="require_totp && !totp_enabled" variant="destructive">
        {{ t('identity.security.requiredNotice') }}
      </Alert>

      <template v-if="pending_totp && !totp_enabled">
        <div class="grid gap-4 md:grid-cols-[auto,1fr]">
          <div class="rounded-md border bg-white p-3" v-html="pending_totp.qr_svg" />
          <div class="space-y-2 text-sm">
            <p>{{ t('identity.security.scanQr') }}</p>
            <p class="break-all font-mono text-xs text-muted-foreground">{{ pending_totp.secret }}</p>
          </div>
        </div>
        <form class="flex flex-wrap items-end gap-3" @submit.prevent="confirmTotp">
          <div class="space-y-2">
            <Label for="confirm_code">{{ t('auth.signIn.totp') }}</Label>
            <Input id="confirm_code" v-model="confirmForm.totp.code" autocomplete="one-time-code" />
          </div>
          <Button type="submit" :disabled="confirmForm.processing">{{ t('identity.security.confirmTotp') }}</Button>
        </form>
      </template>

      <div v-else-if="!totp_enabled">
        <Button type="button" @click="startSetup">{{ t('identity.security.startTotp') }}</Button>
      </div>

      <template v-else>
        <p class="text-sm text-muted-foreground">
          {{ t('identity.security.recoveryCodesRemaining', { count: recovery_codes_remaining }) }}
        </p>
        <form class="space-y-3" @submit.prevent="disableTotp">
          <div class="space-y-2">
            <Label for="disable_password">{{ t('auth.signIn.password') }}</Label>
            <Input id="disable_password" v-model="disableForm.totp.password" type="password" autocomplete="current-password" />
          </div>
          <div class="space-y-2">
            <Label for="disable_code">{{ t('auth.signIn.totp') }}</Label>
            <Input id="disable_code" v-model="disableForm.totp.code" autocomplete="one-time-code" />
          </div>
          <Button type="submit" variant="destructive" :disabled="disableForm.processing">
            {{ t('identity.security.disableTotp') }}
          </Button>
        </form>
      </template>
    </section>

    <div class="flex gap-3">
      <Button as-child variant="outline">
        <Link :href="routes.sessionsManagement">{{ t('identity.sessions.title') }}</Link>
      </Button>
    </div>
  </div>
</template>
