# Security Policy

Thanks for helping keep Vorssaint and the people who use it safe.

## Reporting a vulnerability

Please report security vulnerabilities in private. Do not open a public issue, pull request or discussion for them.

Use GitHub's private vulnerability reporting for this repository.

- **[Report a vulnerability privately](https://github.com/vorssaint/vorssaint-utils/security/advisories/new)**

That opens a private security advisory that only you and the maintainer can see.

<!--
TODO for the maintainer. If you would like to offer a dedicated security contact
email alongside GitHub private advisories, add it here. No private email address
is published in this repository today, so the link above is the canonical route.
-->

When you write it up, please include as much as you can.

- A description of the issue and the impact it could have.
- Steps to reproduce, or a proof of concept.
- The Vorssaint version from Settings under About and your macOS version.

## What to expect

- This is a community project looked after on a best effort basis, so please allow reasonable time for a reply and a fix.
- Please give the maintainer a chance to ship a fix before you talk about the issue in public. That is what coordinated disclosure means.
- Credit goes gladly to reporters who want it.

## Supported versions

Security fixes land on the latest released version. Before you report, please make sure you can reproduce the issue on the most recent release.

## Scope

Vorssaint runs locally and ships as a signed and notarized macOS app. The reports that matter most are the ones that could affect the integrity of the app or its self update flow, or that could let the app's permissions be misused. Issues in the outside services the app merely talks to, like GitHub's releases API or the speed test endpoint, are best taken to those providers.
