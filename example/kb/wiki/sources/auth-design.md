# Auth Design Doc

> **Source:** raw/auth-design.md
> **Ingested:** 2026-04-02
> **Hash:** def6cfd47c2d64d68f11054a4e5bc03abd2213f52a6fd1fb5f9219e84481791b
> **Status:** fresh
> **Chunks:** 3

## Summary
Design document for JWT-based stateless authentication. Covers the full token
lifecycle: login, issuance, refresh, and revocation. Includes security hardening
via one-time refresh tokens, Redis blocklist, rate limiting, and CSRF protection.

## Chunks
### c-1ee0207b: Overview
> We use JWT tokens for stateless authentication. Tokens expire after 24 hours.
> Refresh tokens are stored in httpOnly cookies with a 30-day lifetime.

### c-70eb6658: Token Flow
> User logs in with email/password. Server validates against bcrypt hash. Issues
> JWT (24h) + refresh token (30d). Client stores JWT in memory, refresh in cookie.
> On 401, client uses refresh token to get new JWT.

### c-fcba1172: Security Considerations
> Refresh tokens are rotated on each use (one-time use). Token revocation via
> blocklist in Redis. Rate limiting: 5 login attempts per minute per IP.
> CSRF protection via SameSite=Strict on cookies.

## Key Claims
- JWT tokens expire after 24 hours — c-1ee0207b
- Refresh tokens have 30-day lifetime in httpOnly cookies — c-1ee0207b
- Refresh tokens are one-time use, rotated on each use — c-fcba1172
- Token revocation uses Redis blocklist checked on each request — c-fcba1172
- Login rate limited to 5 attempts/minute/IP — c-fcba1172
- CSRF protection via SameSite=Strict on cookies — c-fcba1172

## Related Concepts
- [jwt-authentication](../concepts/jwt-authentication.md)
- [rate-limiting](../concepts/rate-limiting.md)

<!-- human notes below -->
