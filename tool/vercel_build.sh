#!/usr/bin/env bash
# Builds the CoinScan Flutter web app for Vercel (static hosting only: the API
# runs on Railway).
#
#   bash tool/vercel_build.sh install   fetch the pinned Flutter SDK
#   bash tool/vercel_build.sh build     check settings, build build/web, scan it
#   bash tool/vercel_build.sh scan      re-scan an existing build/web
#
# Every --dart-define value is compiled into public JavaScript. Only these
# public settings are passed: APP_ENV, BACKEND_URL, SUPABASE_URL,
# SUPABASE_ANON_KEY. Backend secrets never belong in the Vercel project.
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.44.4}"
FLUTTER_HOME="${FLUTTER_HOME:-$HOME/flutter-$FLUTTER_VERSION}"
FLUTTER="$FLUTTER_HOME/bin/flutter"

fail() {
  echo "vercel_build: $*" >&2
  exit 1
}

install_flutter() {
  if [ ! -x "$FLUTTER" ]; then
    git clone --depth 1 --branch "$FLUTTER_VERSION" \
      https://github.com/flutter/flutter.git "$FLUTTER_HOME"
  fi
  "$FLUTTER" config --no-analytics >/dev/null
  "$FLUTTER" --version
}

# Prints the "role" claim of a JWT (empty if it has none or cannot be read).
jwt_role() {
  local payload
  payload="$(printf '%s' "$1" | cut -d. -f2 | tr '_-' '/+')"
  while [ $((${#payload} % 4)) -ne 0 ]; do payload="${payload}="; done
  printf '%s' "$payload" | base64 -d 2>/dev/null |
    grep -o '"role" *: *"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/' || true
}

check_public_config() {
  : "${BACKEND_URL:?BACKEND_URL is not set (the CoinScan API URL on Railway, https://...)}"
  : "${SUPABASE_URL:?SUPABASE_URL is not set (https://<project>.supabase.co)}"
  : "${SUPABASE_ANON_KEY:?SUPABASE_ANON_KEY is not set (the public anon / publishable key)}"
  APP_ENV="${APP_ENV:-production}"

  case "$APP_ENV" in production | staging) ;; *) fail "APP_ENV must be production or staging" ;; esac
  case "$BACKEND_URL" in https://*) ;; *) fail "BACKEND_URL must start with https://" ;; esac
  case "$SUPABASE_URL" in https://*) ;; *) fail "SUPABASE_URL must start with https://" ;; esac

  # The most damaging mistake: pasting a Supabase secret / service-role key,
  # which would be published to every visitor.
  case "$SUPABASE_ANON_KEY" in
    sb_secret_*)
      fail "SUPABASE_ANON_KEY is a Supabase secret key. Use the anon / publishable key."
      ;;
    eyJ*)
      local role
      role="$(jwt_role "$SUPABASE_ANON_KEY")"
      [ "$role" = "anon" ] ||
        fail "SUPABASE_ANON_KEY must be the public anon key (JWT role \"anon\"), found \"${role:-unknown}\"."
      ;;
  esac
}

scan_bundle() {
  # Text files only: the compiled Skia binaries contain harmless look-alikes
  # (e.g. the shader built-in "sk_LocalInvocationID"). Key prefixes must be
  # followed by key material: the Supabase client itself contains the bare
  # literal "sb_secret_" to recognise key formats.
  local hits jwt role
  hits="$(grep -rlE --include='*.js' --include='*.json' --include='*.html' \
    '(^|[^A-Za-z0-9_])(AIza[0-9A-Za-z_-]{35}|sk-(proj-)?[A-Za-z0-9_-]{20,}|sk_[A-Za-z0-9]{24,}|sb_secret_[A-Za-z0-9_-]{16,})|-----BEGIN [A-Z ]*PRIVATE KEY|postgres(ql)?(\+asyncpg)?://' \
    build/web || true)"
  [ -z "$hits" ] || fail "possible secret in the web bundle, not publishing: $hits"

  # The only JWT allowed in the bundle is the public anon key.
  while IFS= read -r jwt; do
    [ -n "$jwt" ] || continue
    role="$(jwt_role "$jwt")"
    [ "$role" = "anon" ] ||
      fail "a JWT with role \"${role:-unknown}\" is in the web bundle, not publishing"
  done < <(grep -rhoE --include='*.js' --include='*.json' --include='*.html' \
    'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+' build/web | sort -u || true)

  echo "Bundle check: no secret patterns found in build/web."
}

build_web() {
  check_public_config
  [ -x "$FLUTTER" ] || install_flutter
  "$FLUTTER" build web --release --no-wasm-dry-run \
    --dart-define=APP_ENV="$APP_ENV" \
    --dart-define=BACKEND_URL="$BACKEND_URL" \
    --dart-define=SUPABASE_URL="$SUPABASE_URL" \
    --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
  scan_bundle
}

case "${1:-build}" in
  install) install_flutter ;;
  build) build_web ;;
  scan) scan_bundle ;;
  *) fail "usage: bash tool/vercel_build.sh [install|build|scan]" ;;
esac
