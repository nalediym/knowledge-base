# API Guidelines

> **Source:** raw/api-guidelines.md
> **Ingested:** 2026-04-02
> **Hash:** e5f6g7h8...
> **Status:** fresh
> **Chunks:** 4

## Summary
API conventions document covering authentication requirements, tiered rate limiting,
standardized error response format, and URL-based versioning strategy.

## Chunks
### chunk-1: Authentication
> All API endpoints require a valid JWT in the Authorization header. Tokens are
> issued by the auth service and expire after 24 hours. Use refresh tokens to
> obtain new JWTs without re-authenticating.

### chunk-2: Rate Limiting
> Public endpoints: 100 req/min per IP. Authenticated: 1000 req/min per user.
> Auth endpoints: 5 req/min per IP (login, register, refresh).

### chunk-3: Error Format
> All errors return JSON with error (human-readable), code (machine code), and
> details object.

### chunk-4: Versioning
> API versioned via URL path: /api/v1/, /api/v2/. Breaking changes require a
> new version. Additive changes are allowed in-place.

## Key Claims
- All endpoints require JWT in Authorization header — chunk-1
- JWT tokens expire after 24 hours — chunk-1
- Public rate limit: 100 req/min/IP — chunk-2
- Auth rate limit: 5 req/min/IP — chunk-2
- Errors use standardized JSON format with code field — chunk-3

## Related Concepts
- [jwt-authentication](../concepts/jwt-authentication.md)
- [rate-limiting](../concepts/rate-limiting.md)
