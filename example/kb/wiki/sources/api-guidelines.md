# API Guidelines

> **Source:** raw/api-guidelines.md
> **Ingested:** 2026-04-02
> **Hash:** 801a7403c839732e2af28d16f67d60818b7e0ba269fa153ed8bb7177f14acb98
> **Status:** fresh
> **Chunks:** 4

## Summary
API conventions document covering authentication requirements, tiered rate limiting,
standardized error response format, and URL-based versioning strategy.

## Chunks
### c-81f76c25: Authentication
> All API endpoints require a valid JWT in the Authorization header. Tokens are
> issued by the auth service and expire after 24 hours. Use refresh tokens to
> obtain new JWTs without re-authenticating.

### c-eec47ebf: Rate Limiting
> Public endpoints: 100 req/min per IP. Authenticated: 1000 req/min per user.
> Auth endpoints: 5 req/min per IP (login, register, refresh).

### c-9cecbd3d: Error Format
> All errors return JSON with error (human-readable), code (machine code), and
> details object.

### c-483d4dae: Versioning
> API versioned via URL path: /api/v1/, /api/v2/. Breaking changes require a
> new version. Additive changes are allowed in-place.

## Key Claims
- All endpoints require JWT in Authorization header — c-81f76c25
- JWT tokens expire after 24 hours — c-81f76c25
- Public rate limit: 100 req/min/IP — c-eec47ebf
- Authenticated rate limit: 1000 req/min/user — c-eec47ebf
- Auth rate limit: 5 req/min/IP — c-eec47ebf
- Errors use standardized JSON format with code field — c-9cecbd3d
- API versioned via URL path with breaking changes requiring new version — c-483d4dae

## Related Concepts
- [jwt-authentication](../concepts/jwt-authentication.md)
- [rate-limiting](../concepts/rate-limiting.md)

<!-- human notes below -->
