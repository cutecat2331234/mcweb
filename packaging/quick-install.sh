#!/usr/bin/env bash
# McWeb 发布包快速安装/升级脚本（由 CI 打包时置于发布根目录）
set -euo pipefail

APP_USER="mcweb"
APP_ROOT="/opt/mcweb"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  cat <<EOF
McWeb 快速安装 / 升级

用法:
  sudo ./quick-install.sh              将当前目录部署到 /opt/mcweb 并迁移数据库
  sudo ./quick-install.sh --fresh      先执行 bin/install 完整安装系统依赖与环境

示例:
  tar -xzf mcweb-*.tar.gz
  cd mcweb-*
  sudo ./quick-install.sh
EOF
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "请使用 root 或 sudo 运行" >&2
    exit 1
  fi
}

release_version() {
  if [[ -f "${SOURCE_DIR}/VERSION" ]]; then
    cat "${SOURCE_DIR}/VERSION"
  else
    date +%Y%m%d%H%M%S
  fi
}

deploy_release() {
  local version release_dir
  version="$(release_version)"
  release_dir="${APP_ROOT}/releases/${version}"

  mkdir -p "${APP_ROOT}/releases"
  if [[ -d "${release_dir}" ]]; then
    echo "Release ${version} 已存在，更新文件…"
    rsync -a --delete --exclude='quick-install.sh' "${SOURCE_DIR}/" "${release_dir}/"
  else
    mkdir -p "${release_dir}"
    rsync -a --exclude='quick-install.sh' "${SOURCE_DIR}/" "${release_dir}/"
  fi

  ln -sfn "${release_dir}" "${APP_ROOT}/current"
  chown -R "${APP_USER}:${APP_USER}" "${APP_ROOT}"
  echo "已部署到 ${release_dir}"
}

ensure_bundle_env() {
  local env_file="/etc/mcweb/mcweb.env"
  [[ -f "${env_file}" ]] || return 0
  grep -q '^BUNDLE_DEPLOYMENT=' "${env_file}" || echo 'BUNDLE_DEPLOYMENT=true' >> "${env_file}"
  grep -q '^BUNDLE_WITHOUT=' "${env_file}" || echo 'BUNDLE_WITHOUT=development:test' >> "${env_file}"
}

run_migrate() {
  local env_file="/etc/mcweb/mcweb.env"
  if [[ ! -f "${env_file}" ]]; then
    echo "未找到 ${env_file}，跳过数据库迁移。"
    return 0
  fi

  set -a
  # shellcheck disable=SC1090
  source "${env_file}"
  set +a

  sudo -u "${APP_USER}" env \
    HOME="/home/${APP_USER}" \
    PATH="/home/${APP_USER}/.rbenv/shims:/usr/local/bin:/usr/bin:/bin" \
    BUNDLE_DEPLOYMENT=true \
    BUNDLE_WITHOUT="${BUNDLE_WITHOUT:-development:test}" \
    RAILS_ENV=production \
    bash -c "cd ${APP_ROOT}/current && bundle exec rails db:migrate"
}

restart_services() {
  if systemctl list-unit-files mcweb-web.service >/dev/null 2>&1; then
    systemctl daemon-reload
    systemctl restart mcweb-worker mcweb-web || true
    echo "已重启 mcweb-web / mcweb-worker"
  else
    echo "提示: systemctl enable --now mcweb-web mcweb-worker caddy"
  fi
}

main() {
  require_root

  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
  fi

  if [[ "${1:-}" == "--fresh" ]]; then
    echo "执行完整安装 (bin/install)…"
    bash "${SOURCE_DIR}/bin/install"
  elif ! id -u "${APP_USER}" >/dev/null 2>&1; then
    echo "用户 ${APP_USER} 不存在，使用 --fresh 进行首次安装，或先运行 bin/install" >&2
    exit 1
  fi

  deploy_release
  ensure_bundle_env
  run_migrate
  restart_services

  if [[ -x "${APP_ROOT}/current/bin/doctor" ]]; then
    "${APP_ROOT}/current/bin/doctor" || true
  fi

  echo ""
  echo "McWeb $(release_version) 就绪 → ${APP_ROOT}/current"
  echo "首次部署请运行: sudo -u ${APP_USER} ${APP_ROOT}/current/bin/setup"
}

main "$@"
