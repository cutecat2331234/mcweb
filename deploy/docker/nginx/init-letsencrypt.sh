#!/usr/bin/env bash
# One-time Let's Encrypt bootstrap for the McWeb Docker stack.
#
# nginx will not start while its 443 block points at a certificate that does not
# exist yet, but certbot's HTTP-01 challenge needs nginx already serving :80.
# This script breaks that cycle: it drops in a throwaway self-signed cert, starts
# nginx, then asks certbot for the real certificate and reloads nginx. Ongoing
# renewal is then handled automatically by the long-running `certbot` service.
#
# Usage (run once, from the deploy/docker directory or via its path):
#   cd deploy/docker && cp .env.example .env   # edit MCWEB_DOMAIN / MCWEB_ACME_EMAIL
#   ./nginx/init-letsencrypt.sh
set -euo pipefail

# Work from the compose project root (parent of this nginx/ dir).
cd "$(dirname "$0")/.."

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

domain="${MCWEB_DOMAIN:-}"
email="${MCWEB_ACME_EMAIL:-}"
staging="${CERTBOT_STAGING:-0}"
conf="nginx/mcweb.conf"

if [[ -z "${domain}" || "${domain}" == "example.com" ]]; then
  echo "请先在 deploy/docker/.env 中把 MCWEB_DOMAIN 设为真实域名。" >&2
  exit 1
fi

compose() { docker compose "$@"; }

echo "→ 将 ${conf} 中的 example.com 替换为 ${domain}"
sed -i "s/example\.com/${domain}/g" "${conf}"

echo "→ 生成临时自签证书，让 nginx 能够先启动"
compose run --rm --entrypoint sh certbot -c "\
  mkdir -p /etc/letsencrypt/live/${domain} && \
  openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
    -keyout /etc/letsencrypt/live/${domain}/privkey.pem \
    -out /etc/letsencrypt/live/${domain}/fullchain.pem \
    -subj '/CN=${domain}'"

echo "→ 启动 nginx"
compose up -d nginx

echo "→ 删除临时证书，准备申请正式证书"
compose run --rm --entrypoint sh certbot -c "\
  rm -rf /etc/letsencrypt/live/${domain} \
         /etc/letsencrypt/archive/${domain} \
         /etc/letsencrypt/renewal/${domain}.conf"

email_arg="--register-unsafely-without-email"
[[ -n "${email}" ]] && email_arg="--email ${email}"
staging_arg=""
[[ "${staging}" != "0" ]] && staging_arg="--staging"

echo "→ 向 Let's Encrypt 申请正式证书 (${domain})"
# shellcheck disable=SC2086
compose run --rm --entrypoint certbot certbot certonly --webroot \
  -w /var/www/certbot -d "${domain}" \
  ${email_arg} ${staging_arg} --agree-tos --non-interactive --force-renewal

echo "→ 重新加载 nginx 以启用正式证书"
compose exec nginx nginx -s reload

echo "完成。后续续期由长期运行的 certbot 服务自动处理。"
echo "现在可以启动完整服务栈：docker compose up -d"
