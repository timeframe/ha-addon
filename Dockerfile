FROM ruby:4.0.10-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential git libffi-dev libyaml-dev \
      chromium imagemagick \
      libatk-bridge2.0-0 libatk1.0-0 libcups2 libdbus-1-3 \
      libdrm2 libgbm1 libnspr4 libnss3 libx11-xcb1 \
      libxcomposite1 libxdamage1 libxrandr2 libxshmfence1 \
      fonts-liberation \
      postgresql postgresql-client && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV RAILS_ENV=production

COPY Gemfile Gemfile.lock ./
COPY engine/timeframe-core.gemspec engine/
RUN gem update --system 4.1.0 --no-document && \
    bundle config set --local without 'development test' && \
    bundle config set --local frozen true && \
    bundle install --jobs 4

COPY . .

RUN mkdir -p /data
RUN SECRET_KEY_BASE=precompile \
    TIMEFRAME_HOME_ASSISTANT_TOKEN=precompile \
    RAILS_ENV=production \
    bundle exec rails assets:precompile

ENV PORT=8099

EXPOSE 8099

CMD ["./script/docker-start"]
