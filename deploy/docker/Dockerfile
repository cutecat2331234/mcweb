FROM node:26-bookworm-slim@sha256:cd565714d4da3e84bfd341e31448f81d47c6362198f152345297c9c1154e6341 AS node

FROM ruby:4.0.6-slim-bookworm@sha256:c5650da02325ecb3e7dd96e7074772c3ae2ecd093a9acf2cdbcf1a2fdc680726 AS dependencies

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends build-essential libpq-dev libvips42 && \
    rm -rf /var/lib/apt/lists/*

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx && \
    node --version && npm --version

WORKDIR /app
ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_PATH=/app/vendor/bundle

COPY Gemfile Gemfile.lock package.json package-lock.json ./
RUN bundle install && npm ci

ENV npm_config_offline=true

FROM dependencies AS build

COPY . .
RUN SECRET_KEY_BASE="$(ruby -rsecurerandom -e 'print SecureRandom.hex(64)')" \
    LOCKBOX_MASTER_KEY="$(ruby -rsecurerandom -e 'print SecureRandom.hex(32)')" \
    RAILS_INBOUND_EMAIL_PASSWORD="$(ruby -rsecurerandom -e 'print SecureRandom.hex(32)')" \
    MCWEB_PUBLIC_URL=https://build.mcweb.invalid-domain \
    MCWEB_ALLOWED_HOSTS=build.mcweb.invalid-domain \
    MCWEB_SMTP_ADDRESS=127.0.0.1 \
    MCWEB_SMTP_AUTHENTICATION=none \
    MCWEB_MAIL_FROM=build@mcweb.invalid-domain \
    MCWEB_S3_BUCKET=mcweb-build-private \
    MCWEB_S3_REGION=us-east-1 \
    bundle exec rails assets:precompile && \
    rm -rf node_modules tmp/cache

FROM ruby:4.0.6-slim-bookworm@sha256:c5650da02325ecb3e7dd96e7074772c3ae2ecd093a9acf2cdbcf1a2fdc680726 AS runtime-base

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends curl fonts-noto-cjk libpq5 libvips42 && \
    test -f /usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc && \
    test -f /usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd --system --gid 1000 mcweb && \
    useradd --system --uid 1000 --gid mcweb --create-home --home-dir /home/mcweb mcweb

FROM runtime-base AS runtime

WORKDIR /app
ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_PATH=/app/vendor/bundle

COPY --from=build --chown=mcweb:mcweb /app /app
COPY --from=build /app/bin/docker-entrypoint /usr/bin/docker-entrypoint
RUN chmod 0755 /usr/bin/docker-entrypoint && \
    mkdir -p /var/lib/mcweb /app/log /app/storage /app/tmp/pids && \
    chown -R mcweb:mcweb /var/lib/mcweb /app/log /app/storage /app/tmp

USER mcweb
ENTRYPOINT ["docker-entrypoint"]
EXPOSE 3000
CMD ["web"]
