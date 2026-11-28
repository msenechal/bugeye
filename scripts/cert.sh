#!/usr/bin/env bash
# One time, on the Mac: creates the self-signed "Bugeye Dev" code-signing identity in its own keychain.
# TCC keys permission grants to the signature, so signing every build with this one identity keeps
# Screen Recording and Accessibility grants across installs (design/01 §2.6, design/11 §1).
set -euo pipefail

identity="Bugeye Dev"
keychain="$HOME/Library/Keychains/bugeye-signing.keychain-db"
password="bugeye"  # Protects only this local signing keychain; it holds nothing else.

if [ -f "$keychain" ] && security find-certificate -c "$identity" "$keychain" >/dev/null 2>&1; then
    echo "\"$identity\" already exists in $keychain"
    exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

[ -f "$keychain" ] || security create-keychain -p "$password" "$keychain"
security unlock-keychain -p "$password" "$keychain"
security set-keychain-settings "$keychain"  # No auto-lock.

cat > "$work/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $identity
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

# /usr/bin/openssl is LibreSSL: its PKCS#12 output is importable by `security` (OpenSSL 3's isn't).
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$work/key.pem" -out "$work/cert.pem" -config "$work/cert.cnf"
/usr/bin/openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" -name "$identity" \
    -out "$work/identity.p12" -passout pass:bugeye-p12
security import "$work/identity.p12" -k "$keychain" -P bugeye-p12 -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$keychain" >/dev/null

# Put the keychain in the user's search list if it isn't there yet.
listed=()
while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line#\"}"
    line="${line%\"}"
    [ -n "$line" ] && listed+=("$line")
done < <(security list-keychains -d user)
found=no
for k in ${listed[@]+"${listed[@]}"}; do [ "$k" = "$keychain" ] && found=yes; done
if [ "$found" = no ]; then
    security list-keychains -d user -s ${listed[@]+"${listed[@]}"} "$keychain"
fi

security find-identity -p codesigning "$keychain"
echo "Created \"$identity\". Next: make install"
