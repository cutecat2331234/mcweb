ARG MCWEB_DOWNSTREAM_NODE_PACKAGE_DIR=deploy/cnb/empty-node-package

FROM node:26-bookworm-slim@sha256:cd565714d4da3e84bfd341e31448f81d47c6362198f152345297c9c1154e6341 AS node

FROM ruby:4.0.6-bookworm@sha256:b0bd137e80811fa033491ade503d8b24dbeb5c799fd41f81fe74381fcb20715c

ARG MCWEB_DOWNSTREAM_NODE_PACKAGE_DIR

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      docker.io \
      fonts-noto-cjk \
      git \
      libatomic1 \
      libpq-dev \
      libvips-dev \
      pkg-config && \
    rm -rf /var/lib/apt/lists/*

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx && \
    node --version && npm --version && ruby --version && docker --version

ENV BUNDLE_FROZEN=1 \
    BUNDLE_PATH=/opt/mcweb-quality/vendor/bundle \
    PLAYWRIGHT_BROWSERS_PATH=/opt/mcweb-quality/ms-playwright \
    MCWEB_DOWNSTREAM_NODE_MODULES=/opt/mcweb-quality/downstream-node/node_modules \
    ASTRO_TELEMETRY_DISABLED=1

WORKDIR /opt/mcweb-quality/root
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 8 --retry 3

COPY package.json package-lock.json ./
RUN npm ci --include=dev --no-audit --no-fund

WORKDIR /opt/mcweb-quality/downstream-node
COPY ${MCWEB_DOWNSTREAM_NODE_PACKAGE_DIR}/package.json \
  ${MCWEB_DOWNSTREAM_NODE_PACKAGE_DIR}/package-lock.json ./
RUN npm ci --include=dev --no-audit --no-fund && mkdir -p node_modules

WORKDIR /opt/mcweb-quality/root
RUN ./node_modules/.bin/playwright install --with-deps chromium && \
    rm -rf /var/lib/apt/lists/* && \
    test -x ./node_modules/.bin/tsc && \
    test -d "${MCWEB_DOWNSTREAM_NODE_MODULES}" && \
    find "${PLAYWRIGHT_BROWSERS_PATH}" -type f -name chrome-headless-shell -print -quit | grep -q .

# Dependency installation and browser provisioning happen only while CNB builds
# this cache image. Checked-out source must fail instead of downloading later.
ENV npm_config_offline=true

WORKDIR /workspace
