ARG MCWEB_ACCEPTANCE_RUNNER_BASE
FROM ${MCWEB_ACCEPTANCE_RUNNER_BASE}

RUN groupadd --system --gid 10002 mcweb-acceptance && \
    useradd --system --uid 10002 --gid mcweb-acceptance \
      --home-dir /tmp --shell /usr/sbin/nologin mcweb-acceptance

WORKDIR /workspace
COPY --chown=10002:10002 . .

# The base image owns all locked gems and native tools. This source-only layer
# must remain network-free so CNB can export one immutable acceptance runner.
RUN test -f scripts/run-production-acceptance.sh && bundle check

ENV HOME=/tmp
USER 10002:10002
