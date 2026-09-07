# Security Policy

## Supported versions

Only the most recent release of HamPi / HamPC / HamIQ receives security
updates.

Note that HamPi is a build system: it installs and compiles well over a
hundred third-party amateur radio applications. A vulnerability in one of
those applications belongs upstream with that project. What this policy
covers is the HamPi playbooks themselves — how they fetch sources, what they
install, the permissions they set, and the credentials they handle.

## Reporting a vulnerability

Report vulnerabilities privately through GitHub Security Advisories:

**https://github.com/Dustpan95/HamPi/security/advisories/new**

Please do not open a public issue for a security problem.

Include as much of the following as applies:

* Which component is affected — a playbook under `tasks/`, the inventory
  handling, or one of the scripts in the repository root.
* The commit or release tag you are reporting against.
* The target platform and OS release (for example, Raspberry Pi 5 running
  Raspberry Pi OS Trixie 64-bit).
* What an attacker gains, and what access they need to begin with.
* A CVE number or external reference, if the issue originates in a
  dependency this project pulls in.

If you are unsure whether something qualifies, report it anyway.
