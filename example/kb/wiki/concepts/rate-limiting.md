# Rate Limiting

> **First seen in:** [auth-design](../sources/auth-design.md)
> **Also referenced by:** [api-guidelines](../sources/api-guidelines.md)
> **Confidence:** high (2 sources agree)

## Definition
Tiered request throttling: 5 req/min for auth, 100 req/min for public,
1000 req/min for authenticated endpoints.

## Details
Auth endpoints (login, register, refresh) are limited to 5 requests per minute
per IP — api-guidelines#chunk-2, auth-design#chunk-3. Public endpoints allow
100 req/min per IP. Authenticated endpoints allow 1000 req/min per user —
api-guidelines#chunk-2. The auth rate limit is the strictest tier, shared
between both docs.

## Connections
- Related to: [jwt-authentication](jwt-authentication.md) — rate limiting protects the token issuance flow

## Provenance
- [auth-design.md](../sources/auth-design.md) — chunk-3
- [api-guidelines.md](../sources/api-guidelines.md) — chunk-2
