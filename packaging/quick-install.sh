#!/usr/bin/env bash
# McWeb 发布包快速安装/升级脚本（由 CI 打包时置于发布根目录）
set -euo pipefail

APP_USER="mcweb"
APP_ROOT="/opt/mcweb"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE_VERSION=""
RELEASE_DIR=""

usage() {
  cat <<EOF
McWeb 快速安装 / 升级

用法:
  sudo ./quick-install.sh              放置候选 release，并通过 bin/update 安全升级
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

stage_candidate_release() {
  RELEASE_VERSION="$(release_version)"
  [[ "${RELEASE_VERSION}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
    echo "无效的 release 版本: ${RELEASE_VERSION}" >&2
    exit 1
  }
  [[ "${RELEASE_VERSION}" != "." && "${RELEASE_VERSION}" != ".." ]] || {
    echo "无效的 release 版本: ${RELEASE_VERSION}" >&2
    exit 1
  }
  RELEASE_DIR="${APP_ROOT}/releases/${RELEASE_VERSION}"

  mkdir -p "${APP_ROOT}/releases"
  if [[ -e "${RELEASE_DIR}" || -L "${RELEASE_DIR}" ]]; then
    echo "候选 release 已存在，拒绝覆盖: ${RELEASE_DIR}" >&2
    echo "请直接运行该候选版本的 bin/update，或使用新的 release 版本。" >&2
    exit 1
  fi

  mkdir "${RELEASE_DIR}"
  rsync -a --exclude='quick-install.sh' "${SOURCE_DIR}/" "${RELEASE_DIR}/"
  chown -R "${APP_USER}:${APP_USER}" "${RELEASE_DIR}"
  echo "候选 release 已放置到 ${RELEASE_DIR}"
}

run_safe_update() {
  [[ -x "${RELEASE_DIR}/bin/update" ]] || {
    echo "候选 release 缺少可执行的 bin/update: ${RELEASE_DIR}" >&2
    exit 1
  }

  MCWEB_APP_BASE="${APP_ROOT}" \
    MCWEB_APP_USER="${APP_USER}" \
    "${RELEASE_DIR}/bin/update" \
      --release "${RELEASE_DIR}" \
      --confirm "UPDATE:${RELEASE_VERSION}"
}

main() {
  require_root

  case "${1:-}" in
    --help|-h)
      usage
      exit 0
      ;;
    --fresh)
      [[ $# -eq 1 ]] || {
        echo "--fresh 不接受其他参数" >&2
        exit 1
      }
      if [[ -e "${APP_ROOT}/current" || -L "${APP_ROOT}/current" ]]; then
        echo "--fresh 仅用于没有 current release 的首次安装；现有实例必须走安全更新。" >&2
        exit 1
      fi
      echo "执行完整安装 (bin/install)…"
      (
        cd "${SOURCE_DIR}"
        bash bin/install
      )
      exit 0
      ;;
    "")
      ;;
    *)
      echo "未知参数: $1" >&2
      usage >&2
      exit 1
      ;;
  esac

  [[ -L "${APP_ROOT}/current" ]] || {
    echo "未找到现有 current release；首次安装请使用 --fresh。" >&2
    exit 1
  }
  id -u "${APP_USER}" >/dev/null 2>&1 || {
    echo "用户 ${APP_USER} 不存在；首次安装请使用 --fresh。" >&2
    exit 1
  }

  stage_candidate_release
  run_safe_update

  echo ""
  echo "McWeb ${RELEASE_VERSION} 已通过安全更新流程就绪 → ${APP_ROOT}/current"
}

main "$@"
