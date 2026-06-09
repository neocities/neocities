#!/usr/bin/env bash

set -eu

. .env

docker exec --interactive --tty \
    --env PGPASSWORD="$DATABASE_PASSWORD" \
    "$DATABASE_CONTAINER" \
    psql --username="$DATABASE_USER" "$DATABASE"