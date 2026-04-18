# Security Policy

## Reporting a Vulnerability

To report a security vulnerability in swift-tor, please use [GitHub Security Advisories](https://github.com/21-DOT-DEV/swift-tor/security/advisories).

**Do not file a public issue.**

When reporting, please include:

- A description of the vulnerability
- Steps to reproduce or a proof of concept
- Potential impact assessment (including anonymity impact, if applicable)

We will acknowledge receipt within 7 days and provide an initial assessment as soon as possible.

## Supported Versions

This package is pre-1.0 ([SemVer major version zero](https://semver.org/#spec-item-4)). Only the latest minor release receives security fixes.

| Version | Supported          |
|---------|--------------------|
| 0.1.x   | :white_check_mark: |

## Threat Model & Responsible Use

swift-tor runs the Tor daemon in-process via `libtor`. This has important implications:

- **Anonymity depends on the consuming application.** Process-level hygiene (memory, logging, filesystem, network sandbox) is the host app's responsibility.
- **Never log sensitive material.** Onion-service private keys, control-port passwords, and bootstrap state must stay out of logs and crash reports.
- **Report anonymity-affecting bugs via GHSA**, even if they are not classic CVEs. Traffic analysis leaks, side channels, and fingerprintable behavior qualify.
- **Upstream issues first.** Vulnerabilities in the Tor daemon itself should be reported directly to the [Tor Project](https://support.torproject.org/misc/bug-or-feedback/#report-a-security-issue); this repository will rebase on upstream fixes.

## Upstream Dependencies

This package wraps [Tor](https://gitlab.torproject.org/tpo/core/tor) and links against [OpenSSL](https://www.openssl.org/) (via swift-openssl) and [libevent](https://libevent.org/) (via swift-event).

Vulnerabilities in the underlying libraries should be reported directly to their respective projects:

- **Tor**: See the [Tor Project security reporting process](https://support.torproject.org/misc/bug-or-feedback/#report-a-security-issue) (email: security@torproject.org, or via [HackerOne](https://hackerone.com/torproject)).
- **OpenSSL**: See the [OpenSSL security policy](https://www.openssl.org/policies/general/security-policy.html).
- **libevent**: See [libevent GitHub security advisories](https://github.com/libevent/libevent/security/advisories).
