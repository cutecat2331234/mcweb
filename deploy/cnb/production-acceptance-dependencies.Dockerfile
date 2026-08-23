FROM docker:29.0.4-cli@sha256:858bb1e05af16840f5a55143c3e5e14073891fbc92f2c1f6f38dd9c5f2cca03c AS docker_cli

FROM ruby:4.0.6-bookworm@sha256:b0bd137e80811fa033491ade503d8b24dbeb5c799fd41f81fe74381fcb20715c

COPY --from=docker_cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker_cli /usr/local/libexec/docker/cli-plugins/docker-compose \
  /usr/local/libexec/docker/cli-plugins/docker-compose

COPY deploy/cnb/postgresql-client-cache.version /tmp/postgresql-client-cache.version

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      fonts-noto-cjk \
      gnupg \
      libvips-dev \
      openssl && \
    install -d -m 0755 /usr/share/postgresql-common/pgdg && \
    curl --fail --silent --show-error --retry 3 \
      https://www.postgresql.org/media/keys/ACCC4CF8.asc \
      --output /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc && \
    gpg --show-keys --with-colons \
      /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc | \
      grep -q '^fpr:::::::::B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8:' && \
    echo 'deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt-archive.postgresql.org/pub/repos/apt bookworm-pgdg-archive main' \
      > /etc/apt/sources.list.d/pgdg-archive.list && \
    apt-get update -qq && \
    postgresql_client_version="$(cat /tmp/postgresql-client-cache.version)" && \
    apt-get install -y --no-install-recommends \
      "libpq5=${postgresql_client_version}" \
      "libpq-dev=${postgresql_client_version}" \
      "postgresql-client-18=${postgresql_client_version}" && \
    rm -f /tmp/postgresql-client-cache.version && \
    rm -rf /var/lib/apt/lists/* && \
    docker --version && \
    docker compose version && \
    pg_dump --version | grep -Eq ' 18\.' && \
    pg_restore --version | grep -Eq ' 18\.'

ENV BUNDLE_DEPLOYMENT=1 \
    BUNDLE_DISABLE_VERSION_CHECK=1 \
    BUNDLE_FROZEN=1 \
    BUNDLE_PATH=/opt/mcweb-production-acceptance/vendor/bundle \
    BUNDLE_WITHOUT="development:test"

WORKDIR /opt/mcweb-production-acceptance
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 8 --retry 3 && bundle check

# CNB builds this image only when its pinned inputs change. The checked-out
# source uses the installed bundle and tools without package-manager downloads.
WORKDIR /workspace
