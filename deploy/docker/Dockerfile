FROM ruby:3.4.9-slim-bookworm AS base

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends curl libpq-dev nodejs npm && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_PATH=/app/vendor/bundle

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .
RUN npm ci && \
    bundle exec rails assets:precompile && \
    npm ci --omit=dev

COPY bin/docker-entrypoint /usr/bin/
ENTRYPOINT ["docker-entrypoint"]
EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
