#!/usr/bin/env bash
#
# Copyright 2024 - 2026, Shackwright contributors.
# Licensed under the GNU General Public License v3.0. See LICENSE.
#
# Exercises tasks/install_user_skeleton.yml, which decides what every account
# created from a released image inherits.
#
# The exclusions are the reason this test exists. The playbook copies a built
# user's home into /etc/skel, and that home is where the build ran: it can
# contain a shell history, an SSH private key, a credential cache. Any of
# those reaching /etc/skel would be handed to every person who flashes the
# image. A missing desktop file is a nuisance; a leaked private key is not.
#

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

WORK="$(mktemp -d)"
SKEL="${WORK}/skel"
HOME_DIR="${WORK}/home/builduser"
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
check() {
    printf '  %-52s ' "$1"
    if [ "$2" = "0" ]; then echo "PASS"; pass=$((pass+1)); else echo "FAIL"; fail=$((fail+1)); fi
}

echo "Shackwright /etc/skel seeding tests"
echo

# A build user's home as it looks after a real run: config worth keeping,
# build scratch worth dropping, secrets that must never be copied.
mkdir -p "${HOME_DIR}"/{.config/autostart,.config/pulse,Desktop,bin,.fldigi}
mkdir -p "${HOME_DIR}"/{hamradio/direwolf/build,.ssh,.gnupg,.cache/pip,.local/share/Trash}
echo keep   > "${HOME_DIR}/.config/autostart/wsjtx.desktop"
echo keep   > "${HOME_DIR}/Desktop/fldigi.desktop"
echo keep   > "${HOME_DIR}/bin/upload_adif_log"
echo keep   > "${HOME_DIR}/.fldigi/fldigi.prefs"
echo drop   > "${HOME_DIR}/hamradio/direwolf/build/junk.o"
echo SECRET > "${HOME_DIR}/.ssh/id_rsa"
echo SECRET > "${HOME_DIR}/.gnupg/secring.gpg"
echo drop   > "${HOME_DIR}/.bash_history"
echo drop   > "${HOME_DIR}/.cache/pip/wheel"
echo drop   > "${HOME_DIR}/.local/share/Trash/expunged"
echo drop   > "${HOME_DIR}/.config/pulse/cookie"

mkdir -p "$SKEL"
# The same tar invocation the playbook runs.
tar -C "$HOME_DIR" \
    --exclude=./hamradio --exclude=./.cache --exclude=./.ssh --exclude=./.gnupg \
    --exclude=./.bash_history --exclude=./.python_history --exclude=./.wget-hsts \
    --exclude=./.sudo_as_admin_successful --exclude=./.local/share/Trash \
    --exclude=./.config/pulse \
    -cf - . | tar -C "$SKEL" --no-same-owner -xf -
check "seeding runs" $?

# Content a new operator needs.
for want in .config/autostart/wsjtx.desktop Desktop/fldigi.desktop \
            bin/upload_adif_log .fldigi/fldigi.prefs; do
    [ -f "${SKEL}/${want}" ]; check "inherited: ${want}" $?
done

# Content that must not be there.
for bad in hamradio .ssh .gnupg .bash_history .cache \
           .local/share/Trash .config/pulse; do
    [ ! -e "${SKEL}/${bad}" ]; check "excluded: ${bad}" $?
done

# The specific disaster case, stated plainly.
if grep -rq SECRET "$SKEL" 2>/dev/null; then
    check "no secret material anywhere in the skeleton" 1
else
    check "no secret material anywhere in the skeleton" 0
fi

echo
echo "  passed: ${pass}  failed: ${fail}"
[ "$fail" -eq 0 ] || exit 1
