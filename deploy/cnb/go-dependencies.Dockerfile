FROM golang:1.26.5-bookworm@sha256:53eeac89074db483fdf0ab3be1df32bf6e47562263d2d0d6baa7f26acb4957dd

ENV GOTOOLCHAIN=local

WORKDIR /opt/mcweb-dependency-cache

COPY host/mcweb-hostd/go.mod host/mcweb-hostd/go.sum ./host/mcweb-hostd/
COPY nodes/mcweb-node/go.mod nodes/mcweb-node/go.sum ./nodes/mcweb-node/

RUN set -eu; \
    for module in host/mcweb-hostd nodes/mcweb-node; do \
      (cd "${module}" && go mod download); \
    done

WORKDIR /workspace
