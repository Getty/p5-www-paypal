# WWW::PayPal House Rules

The shared house rules come from skilletor — bundle `getty-cpan-dist@getty`: engineering
discipline, the delegation lock, the publish gate, karr coordination, CPAN release. They load
as `.claude/rules/.local.*.md`; if they are missing, run `skilletor sync` and publish nothing
until they load. This file adds what is true only here, and wins where it differs.

## What this repo is

Perl client for the PayPal REST API. Scope is two use cases (one-off purchase, monthly
subscription); a feature neither needs does not go in. Read first: `Role::HTTP`,
`Role::OpenAPI` and one existing controller/entity pair — every controller looks the same on
purpose.

## Agent team

| Task | Agent |
|---|---|
| Implement / refactor / debug anything under `lib/`, `examples/` | `www-paypal-worker` (default) |
| Write or extend tests in `t/` | `www-paypal-test-writer` |
| POD, `Changes`, the consumer skill `perl-www-paypal` | `www-paypal-doc-writer` |
| Commits, `Changes`, card → done, pre-release audit | `www-paypal-release-manager` |
| Payment/subscription flow design or review, webhooks, billing data model | `paypal-expert` |
| Read-only research, audit, gap analysis | `www-paypal-worker` ("read-only, change nothing") |

`paypal-expert` is un-prefixed but a team agent all the same.

Behavior-relevant = anything under `lib/` and `t/`, the operation tables, the public API,
error handling, `cpanfile`, `dist.ini`. Prose docs and `Changes` notes are not.

## Release

After any `dzil build`, run `dzil clean`. "Tests pass" is wrong if the run wasn't recursive
(`prove -lr t/`).

## Hazards — the short form (mechanism and background: skill `www-paypal-core`)

- **Tests must never reach PayPal.** No credentials, no network in `t/`. Recorded JSON
  payloads only; anything needing a token lives in `examples/`.
- **Only `www-paypal-core`, `paypal-integration` and `perl-www-paypal` are owned here.** The
  other skills under `.claude/skills/` are skilletor install artifacts; an edit there is
  overwritten by the next sync — change them in their source.
- **Sandbox and live ids are not interchangeable.** Never put one in a code constant or a
  test fixture that could be mistaken for config.

## Conventions — reference, don't restate

Perl house style, Moo patterns, POD directives, `cpanfile` pinning, the next-version scheme and
the `Changes`/`{{$NEXT}}` handling live in skills `getty-perl-core`, `getty-perl-moo`,
`getty-perl-release-author-getty` and `perl-release-dist-ini`. The distribution's own
architecture is skill `www-paypal-core`; PayPal's domain model is `paypal-integration`.
