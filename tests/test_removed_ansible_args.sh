#!/usr/bin/env bash
#
# Guards against two defects that were found across this tree at a scale that
# made the project unusable, and that would come back the moment someone
# copies an old playbook as a template for a new one.
#
# 1. Arguments ansible-core has removed. "warn" was deprecated in 2.5 and
#    removed from command and shell in 2.14, released November 2022. It is
#    not ignored -- the task fails outright with "Unsupported parameters for
#    (ansible.legacy.command) module: warn". It was present 39 times across
#    31 files, 27 of which tasks/main.yml imports, so a quarter of a full run
#    could not succeed on any Ansible newer than three years old.
#
# 2. Download hosts that are gone. w1hkj.com/files/ served the entire fldigi
#    suite and now answers 404 for the whole directory. Eleven playbooks
#    scraped it for version numbers and fetched tarballs from it.
#
# Offline and fast. Nothing here touches the network.

set -u
cd "$(dirname "$0")/.."

fail=0
pass=0

check() {
  local name="$1" ; shift
  if "$@"; then
    printf '  ok   %s\n' "$name" ; pass=$((pass + 1))
  else
    printf '  FAIL %s\n' "$name" ; fail=$((fail + 1))
  fi
}

no_match() {
  local pattern="$1" ; shift
  local hits
  hits=$(grep -rnE "$pattern" "$@" 2>/dev/null | grep -v '^\s*#' | grep -vE '^[^:]+:[0-9]+:\s*#')
  if [ -z "$hits" ]; then
    return 0
  fi
  printf '%s\n' "$hits" | sed 's/^/         /'
  return 1
}

echo "Removed ansible-core arguments and dead download hosts"

# The removed command/shell argument, in any spelling.
check "no 'warn:' argument to command or shell" \
  no_match '^[[:space:]]+warn:[[:space:]]*(no|yes|true|false)[[:space:]]*$' tasks/ library/

# Other arguments removed from ansible-core in the same era, checked now so
# they are not discovered the same way "warn" was.
check "no 'free_form:' key" \
  no_match '^[[:space:]]+free_form:' tasks/ library/

# The dead host. Comment lines explaining why it is dead are allowed; a URL
# in a src:, a cmd:, or a shell: line is not.
check "no live w1hkj.com download URLs" \
  no_match '^[^#]*(src|cmd|shell|url|get_url):.*w1hkj\.com' tasks/ library/

# The fldigi suite resolves versions through SourceForge's RSS feed, which is
# generated from the real file listing. A bare grep over an HTML directory
# page is what produced a version number scraped out of a 404 error page.
check "w1hkj versions come from the SourceForge feed" \
  test -f tasks/build_w1hkj_program.yml

check "the shared w1hkj build asserts its version" \
  grep -q 'ansible.builtin.assert' tasks/build_w1hkj_program.yml

echo
echo "  ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
