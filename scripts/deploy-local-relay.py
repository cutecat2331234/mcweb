#!/usr/bin/env python3
"""Deploy mcweb via local relay: GitHub artifact -> local -> SFTP -> quick-install.

Usage:
  python scripts/deploy-local-relay.py --sha 36e2ded58c8f --artifact-id 7702288313
  python scripts/deploy-local-relay.py --sha 36e2ded58c8f  # artifact-id optional if zip cached

Environment:
  GITHUB_TOKEN   GitHub PAT with actions:read
  MCWEB_SSH_HOST, MCWEB_SSH_USER, MCWEB_SSH_PASSWORD (optional overrides)
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import time
import zipfile
from pathlib import Path

import paramiko

DEFAULT_HOST = os.environ.get("MCWEB_SSH_HOST", "111.170.170.147")
DEFAULT_USER = os.environ.get("MCWEB_SSH_USER", "root")


def require_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise SystemExit(f"Missing required environment variable: {name}")
    return value
WORK_ROOT = Path(__file__).resolve().parent.parent / "tmp" / "deploy"


def log(msg: str) -> None:
    print(msg, flush=True)


def paths(version: str) -> dict[str, Path | str]:
    root = WORK_ROOT
    return {
        "root": root,
        "zip": root / f"mcweb-artifact-{version}.zip",
        "extract": root / f"artifact-{version}",
        "tarball": root / f"mcweb-{version}.tar.gz",
        "remote_tarball": f"/tmp/mcweb-{version}.tar.gz",
        "remote_dir": f"/tmp/mcweb-release-{version}",
    }


def download_local(p: dict, artifact_id: str, expected_bytes: int | None) -> None:
    github_token = require_env("GITHUB_TOKEN")
    p["root"].mkdir(parents=True, exist_ok=True)
    zip_path: Path = p["zip"]
    url = f"https://api.github.com/repos/cutecat2331234/mcweb/actions/artifacts/{artifact_id}/zip"

    if zip_path.exists() and expected_bytes and zip_path.stat().st_size == expected_bytes:
        log(f"Local zip already complete: {zip_path.stat().st_size} bytes")
        return

    for attempt in range(1, 4):
        try:
            log(f"$ curl -C - (attempt {attempt})")
            subprocess.run(
                [
                    "curl.exe", "-fSL", "-C", "-",
                    "-H", f"Authorization: token {github_token}",
                    "-o", str(zip_path), url,
                ],
                check=True,
            )
            size = zip_path.stat().st_size
            log(f"Downloaded {size} bytes")
            if expected_bytes and size != expected_bytes:
                raise RuntimeError(f"zip size mismatch: {size} != {expected_bytes}")
            return
        except Exception as exc:
            log(f"Download attempt {attempt} failed: {exc}")
            time.sleep(5)
    raise RuntimeError("local download failed")


def extract_tarball(p: dict, version: str) -> None:
    tarball: Path = p["tarball"]
    if tarball.exists() and tarball.stat().st_size > 50_000_000:
        log(f"Tarball ready: {tarball}")
        return

    extract: Path = p["extract"]
    if extract.exists():
        shutil.rmtree(extract)
    extract.mkdir(parents=True)

    with zipfile.ZipFile(p["zip"]) as zf:
        zf.extractall(extract)

    candidates = sorted(extract.glob("mcweb-*.tar.gz"), key=lambda x: x.stat().st_size, reverse=True)
    if not candidates:
        raise RuntimeError("no mcweb-*.tar.gz in artifact zip")
    shutil.copy2(candidates[0], tarball)
    log(f"Prepared tarball: {tarball} ({tarball.stat().st_size} bytes)")


def ssh_connect(host: str, user: str, password: str) -> paramiko.SSHClient:
    last: Exception | None = None
    for attempt in range(1, 4):
        try:
            client = paramiko.SSHClient()
            client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            client.connect(host, username=user, password=password, timeout=60)
            return client
        except Exception as exc:
            last = exc
            log(f"SSH attempt {attempt} failed: {exc}")
            time.sleep(5)
    raise last or RuntimeError("SSH failed")


def upload_tarball(p: dict, host: str, user: str, password: str) -> None:
    local_path: Path = p["tarball"]
    remote_path: str = p["remote_tarball"]
    local_size = local_path.stat().st_size

    client = ssh_connect(host, user, password)
    sftp = client.open_sftp()
    try:
        remote_size = sftp.stat(remote_path).st_size
    except OSError:
        remote_size = 0

    if remote_size >= local_size:
        log(f"Remote tarball already complete: {remote_size} bytes")
        sftp.close()
        client.close()
        return

    if remote_size > local_size:
        sftp.remove(remote_path)
        remote_size = 0

    log(f"Uploading {local_size - remote_size} bytes (resume from {remote_size})...")
    with local_path.open("rb") as src:
        src.seek(remote_size)
        with sftp.file(remote_path, "ab" if remote_size else "wb") as dst:
            dst.set_pipelined(True)
            sent = remote_size
            chunk = 1024 * 1024
            while True:
                data = src.read(chunk)
                if not data:
                    break
                dst.write(data)
                sent += len(data)
                if sent % (10 * 1024 * 1024) < chunk:
                    log(f"  uploaded {sent}/{local_size} ({100 * sent // local_size}%)")

    if sftp.stat(remote_path).st_size != local_size:
        raise RuntimeError("upload size mismatch")
    log("Upload complete")
    sftp.close()
    client.close()


def install_remote(p: dict, version: str, host: str, user: str, password: str) -> str:
    bundle = "/home/mcweb/.rbenv/shims/bundle"
    script = f"""
set -euo pipefail
rm -rf '{p["remote_dir"]}'
mkdir -p '{p["remote_dir"]}'
tar -xzf '{p["remote_tarball"]}' -C '{p["remote_dir"]}' --strip-components=1
cd '{p["remote_dir"]}'
chmod +x quick-install.sh
if ! ./quick-install.sh; then
  echo "quick-install failed, finishing migrate + restart..."
  sudo -u mcweb bash -c "
    set -a
    source /etc/mcweb/mcweb.env
    set +a
    export RAILS_ENV=production
    cd /opt/mcweb/current
    {bundle} exec rails db:migrate
  " || true
  systemctl restart mcweb-web mcweb-worker
fi
for i in 1 2 3 4 5 6 7 8 9 10; do
  if systemctl is-active --quiet mcweb-web mcweb-worker && curl -fsS http://127.0.0.1:3000/health/live >/dev/null 2>&1; then
    break
  fi
  if [ "$i" -eq 10 ]; then
    echo "health check failed after retries" >&2
    systemctl status mcweb-web --no-pager -l | tail -20 >&2 || true
    exit 1
  fi
  sleep 3
done
systemctl is-active mcweb-web mcweb-worker
curl -fsS http://127.0.0.1:3000/health/live
echo
cat /opt/mcweb/current/VERSION
"""
    client = ssh_connect(host, user, password)
    _, stdout, stderr = client.exec_command(script, get_pty=True, timeout=3600)
    out = stdout.read().decode("utf-8", "replace")
    err = stderr.read().decode("utf-8", "replace")
    code = stdout.channel.recv_exit_status()
    client.close()
    print(out)
    if err:
        print(err)
    if code != 0:
        raise RuntimeError(f"remote install failed with code {code}")
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description="Deploy mcweb via local relay")
    parser.add_argument("--sha", required=True, help="Release version / git SHA prefix")
    parser.add_argument("--artifact-id", help="GitHub Actions artifact ID")
    parser.add_argument("--expected-bytes", type=int, help="Expected zip size for validation")
    parser.add_argument("--host", default=os.environ.get("MCWEB_SSH_HOST", DEFAULT_HOST))
    parser.add_argument("--user", default=os.environ.get("MCWEB_SSH_USER", DEFAULT_USER))
    parser.add_argument("--password", default=os.environ.get("MCWEB_SSH_PASSWORD"))
    args = parser.parse_args()

    if not args.artifact_id:
        raise SystemExit("--artifact-id is required unless zip is already cached")

    if not args.password:
        args.password = require_env("MCWEB_SSH_PASSWORD")

    p = paths(args.sha)
    log(f"=== Deploy {args.sha} via local relay ===")
    download_local(p, args.artifact_id, args.expected_bytes)
    extract_tarball(p, args.sha)
    upload_tarball(p, args.host, args.user, args.password)
    out = install_remote(p, args.sha, args.host, args.user, args.password)
    if args.sha not in out:
        raise RuntimeError("VERSION mismatch after install")
    log(f"=== Done: https://{args.host}/app ===")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        log(f"ERROR: {exc}")
        raise SystemExit(1)
