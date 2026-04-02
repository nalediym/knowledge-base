# JWT Authentication

> **First seen in:** [auth-design](../sources/auth-design.md)
> **Also referenced by:** [api-guidelines](../sources/api-guidelines.md)
> **Confidence:** high (2 sources agree)

## Definition
Stateless authentication using JSON Web Tokens with a 24-hour expiry,
paired with httpOnly refresh tokens (30-day lifetime) for session continuity.

## Details
The auth service issues JWTs on login after validating credentials against
bcrypt hashes — auth-design#chunk-2. All API endpoints require a valid JWT
in the Authorization header — api-guidelines#chunk-1. On token expiry (401),
clients use refresh tokens to obtain new JWTs without re-authenticating —
auth-design#chunk-2. Refresh tokens are one-time use and rotated on each
exchange — auth-design#chunk-3. Revocation is handled via a Redis blocklist
checked on every request — auth-design#chunk-3.

## Connections
- Related to: [rate-limiting](rate-limiting.md) — auth endpoints share the 5 req/min/IP limit

## Provenance
- [auth-design.md](../sources/auth-design.md) — chunk-1, chunk-2, chunk-3
- [api-guidelines.md](../sources/api-guidelines.md) — chunk-1
