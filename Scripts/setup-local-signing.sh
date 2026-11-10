#!/bin/bash
# Creates a local, self-signed code-signing identity for Sunroom.
#
# Why: TCC (Accessibility, Screen Recording) pins permission grants to a code
# signature. Ad-hoc signatures are pinned to a hash that changes on every build,
# so each rebuild silently revokes the grant. A stable local certificate gives a
# stable designated requirement without using any Apple Developer team,
# organisation or account.
#
# The certificate lives in its own keychain (SunroomLocal.keychain-db) and is
# never added to the System trust store. Nothing leaves the machine.
#
#   ./Scripts/setup-local-signing.sh
#
# Remove with:
#   security delete-keychain ~/Library/Keychains/SunroomLocal.keychain-db

set -euo pipefail

IDENTITY_NAME="Sunroom Local Signing"
KEYCHAIN="$HOME/Library/Keychains/SunroomLocal.keychain-db"
KEYCHAIN_PASSWORD="sunroom-local"

if security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY_NAME"; then
  echo "==> '$IDENTITY_NAME' already exists in $KEYCHAIN"
else
  echo "==> Creating '$IDENTITY_NAME'"
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT

  /usr/bin/openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -subj "/CN=$IDENTITY_NAME" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

  /usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/identity.p12" -passout "pass:$KEYCHAIN_PASSWORD" \
    -name "$IDENTITY_NAME" >/dev/null 2>&1

  if [ ! -f "$KEYCHAIN" ]; then
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  fi
  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$KEYCHAIN_PASSWORD" \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null 2>&1 || true
  # Keep it unlocked for the session; it is a local dev identity.
  security set-keychain-settings -lut 21600 "$KEYCHAIN"
fi

# Make sure codesign can find it without disturbing the login keychain.
EXISTING="$(security list-keychains -d user | tr -d '"' | xargs)"
if ! echo "$EXISTING" | grep -q "SunroomLocal.keychain-db"; then
  # shellcheck disable=SC2086
  security list-keychains -d user -s $EXISTING "$KEYCHAIN"
fi

echo "==> Ready: $(security find-identity -v -p codesigning "$KEYCHAIN" | head -1)"
