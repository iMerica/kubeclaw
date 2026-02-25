# Security Policy

KubeClaw is a production-focused project and we treat security reports seriously.

## Reporting a Vulnerability

Please do not open public GitHub issues for vulnerabilities.

Report security issues privately:
- Email: `security@kubeclaw.ai`
- Subject: `KubeClaw security report`
- Include: affected version, impact, reproduction steps, and any mitigations/workarounds

If encrypted communication is preferred, mention that in the email and we will coordinate a secure channel.

## What to Expect

- Initial response target: within 3 business days
- Triage and severity assessment: as quickly as possible based on impact
- Fix and disclosure timeline: coordinated with reporter, with priority on user safety

We may ask for additional validation details during triage.

## Supported Versions

Security fixes are prioritized for:
- Latest chart release
- Previous minor release, when feasible

Older releases may receive best-effort guidance instead of patch backports.

## Scope Notes

When reporting, include whether the issue affects:
- Helm chart templates/defaults
- CI/release pipeline behavior
- Documentation that could lead to insecure deployment

For upstream runtime issues in OpenClaw itself, please also consider reporting to the upstream OpenClaw project.

Thank you for helping keep KubeClaw users safe.
