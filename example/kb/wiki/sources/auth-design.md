# Auth Design Doc

> **Source:** raw/auth-design.md
> **Ingested:** 2026-04-02
> **Hash:** a1b2c3d4...
> **Status:** fresh
> **Chunks:** 3

## Summary
Design document for JWT-based stateless authentication. Covers the full token
lifecycle: login, issuance, refresh, and revocation. Includes security hardening
via one-time refresh tokens, Redis blocklist, rate limiting, and CSRF protection.

## Chunks
### chunk-1: Overview
> We use JWT tokens for stateless authentication. Tokens expire after 24 hours.
> Refresh tokens are stored in httpOnly cookies with a 30-day lifetime.

### chunk-2: Token Flow
> User logs in with email/password. Server validates against bcrypt hash. Issues
> JWT (24h) + refresh token (30d). Client stores JWT in memory, refresh in cookie.
> On 401, client uses refresh token to get new JWT.

### chunk-3: Security Considerations
> Refresh tokens are rotated on each use (one-time use). Token revocation via
> blocklist in Redis. Rate limiting: 5 login attempts per minute per IP.
> CSRF protection via SameSite=Strict on cookies.

## Key Claims
- JWT tokens expire after 24 hours — chunk-1
- Refresh tokens have 30-day lifetime in httpOnly cookies — chunk-1
- Refresh tokens are one-time use, rotated on each use — chunk-3
- Token revocation uses Redis blocklist checked on each request — chunk-3
- Login rate limited to 5 attempts/minute/IP — chunk-3

## Related Concepts
- [jwt-authentication](../concepts/jwt-authentication.md)
- [rate-limiting](../concepts/rate-limiting.md)
