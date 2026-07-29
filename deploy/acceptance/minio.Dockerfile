FROM golang:1.24.8-bookworm AS build

# The upstream 2025-10-15 security release is source-only. Build that exact
# signed release instead of silently falling back to the older container tag.
ARG MINIO_REF=RELEASE.2025-10-15T17-29-55Z
RUN CGO_ENABLED=0 GOBIN=/out go install -trimpath "github.com/minio/minio@${MINIO_REF}"

FROM debian:bookworm-slim

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends ca-certificates curl && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd --system --gid 10001 minio && \
    useradd --system --uid 10001 --gid minio --home-dir /var/lib/minio minio && \
    install -d -o minio -g minio /data /var/lib/minio

COPY --from=build /out/minio /usr/local/bin/minio

USER minio
EXPOSE 9000
ENTRYPOINT ["minio"]
