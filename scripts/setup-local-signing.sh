#!/bin/sh
set -eu

identity_name=${SHELTERBAR_LOCAL_SIGNING_NAME:-"ShelterBar Local Code Signing"}
keychain_path=$(security default-keychain -d user \
    | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//')

if [ -z "$keychain_path" ] || [ ! -f "$keychain_path" ]; then
    echo "Could not locate the user's default keychain." >&2
    exit 1
fi
if ! command -v openssl >/dev/null 2>&1; then
    echo "OpenSSL is required to create the local code-signing identity." >&2
    exit 1
fi

find_identity() {
    security find-identity -v -p codesigning "$keychain_path" 2>/dev/null \
        | awk -v name="$identity_name" 'index($0, "\"" name "\"") { print $2; exit }'
}

identity_hash=$(find_identity)
if [ -n "$identity_hash" ]; then
    echo "Local signing identity already exists: $identity_name ($identity_hash)"
    exit 0
fi

if security find-certificate -c "$identity_name" "$keychain_path" >/dev/null 2>&1; then
    echo "A certificate named '$identity_name' exists without a usable private key." >&2
    echo "Remove or repair that certificate in Keychain Access before retrying." >&2
    exit 1
fi

temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/ShelterBar-signing.XXXXXX")
cleanup() {
    find "$temporary_dir" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT INT TERM
umask 077

private_key="$temporary_dir/private-key.pem"
certificate="$temporary_dir/certificate.pem"
identity_bundle="$temporary_dir/identity.p12"
bundle_password=$(openssl rand -hex 24)

openssl req -new -newkey rsa:3072 -x509 -sha256 -days 3650 -nodes \
    -subj "/CN=$identity_name/O=ShelterBar Local Development" \
    -addext "basicConstraints=critical,CA:FALSE" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -keyout "$private_key" \
    -out "$certificate" >/dev/null 2>&1

# The PKCS#12 file is short-lived, mode 0600, and removed by the trap. The
# imported private key is marked non-extractable and limited to codesign.
openssl pkcs12 -export -legacy \
    -inkey "$private_key" \
    -in "$certificate" \
    -name "$identity_name" \
    -passout "pass:$bundle_password" \
    -out "$identity_bundle"
security import "$identity_bundle" \
    -k "$keychain_path" \
    -f pkcs12 \
    -P "$bundle_password" \
    -x \
    -T /usr/bin/codesign >/dev/null
unset bundle_password
security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "$keychain_path" \
    "$certificate"

identity_hash=$(find_identity)
if [ -z "$identity_hash" ]; then
    echo "The certificate was imported, but macOS does not consider it a valid code-signing identity." >&2
    exit 1
fi

echo "Created local signing identity: $identity_name ($identity_hash)"
