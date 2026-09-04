ARG MCWEB_ACCEPTANCE_RUNNER_BASE=mcweb-production-acceptance-base:required
FROM ${MCWEB_ACCEPTANCE_RUNNER_BASE}

RUN groupadd --system --gid 10002 mcweb-acceptance && \
    useradd --system --uid 10002 --gid mcweb-acceptance \
      --home-dir /tmp --shell /usr/sbin/nologin mcweb-acceptance

WORKDIR /workspace
COPY --chown=10002:10002 . .

# The explicitly selected base owns all locked gems and native tools. The
# lifecycle stage builds this source-only layer with network access disabled.
RUN test -f scripts/run-production-acceptance.sh && bundle check

ENV HOME=/tmp
USER 10002:10002
