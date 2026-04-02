# JWT Authentication

> **First seen in:** [auth-design](../sources/auth-design.md)
> **Also referenced by:** [api-guidelines](../sources/api-guidelines.md)
> **Confidence:** high (2 sources agree)

## Definition
Stateless authentication using JSON Web Tokens with a 24-hour expiry,
paired with httpOnly refresh tokens (30-day lifetime) for session continuity.

## Details
The auth service issues JWTs on login after validating credentials against
bcrypt hashes — [auth-design](../sources/auth-design.md)#c-70eb6658. All API
endpoints require a valid JWT in the Authorization header —
[api-guidelines](../sources/api-guidelines.md)#c-81f76c25. On token expiry
(401), clients use refresh tokens to obtain new JWTs without re-authenticating
— [auth-design](../sources/auth-design.md)#c-70eb6658. Refresh tokens are
one-time use and rotated on each exchange —
[auth-design](../sources/auth-design.md)#c-fcba1172. Revocation is handled
via a Redis blocklist checked on every request —
[auth-design](../sources/auth-design.md)#c-fcba1172.

## Connections
- Related to: [rate-limiting](rate-limiting.md) — auth endpoints share the 5 req/min/IP limit

## Provenance
- [auth-design.md](../sources/auth-design.md) — c-1ee0207b, c-70eb6658, c-fcba1172
- [api-guidelines.md](../sources/api-guidelines.md) — c-81f76c25

<!-- human notes below -->

## My Notes
The 24h expiry is too long for admin endpoints. We should use 1h for /admin/*.
**REVIEWED** [sha256:f9e8d7c6] — verified against prod config 2026-04-01
