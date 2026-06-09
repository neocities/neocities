FROM ruby:3.3-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    RACK_ENV=development

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    file \
    git \
    imagemagick \
    jpegoptim \
    libcurl4-openssl-dev \
    libffi-dev \
    libimlib2-dev \
    libmagic-dev \
    libmagickwand-dev \
    libpq-dev \
    libreadline-dev \
    libsqlite3-dev \
    libssl-dev \
    libwebp-dev \
    libxml2-dev \
    libxslt1-dev \
    libyaml-dev \
    optipng \
    pngquant \
    postgresql-client \
    sqlite3 \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

# Ensure gitignored directories and seed files exist in the image layer
# (the entrypoint also handles this for volume-mounted dev setups)
RUN mkdir -p public/sites public/site_thumbnails public/site_screenshots \
             public/banned_sites public/deleted_sites \
    && touch files/disposable_email_blacklist.conf \
             files/disposable_email_whitelist.conf

EXPOSE 9292

ENTRYPOINT ["./docker/docker-entrypoint.sh"]
CMD ["web"]
