# Auth Design Doc

## Overview
We use JWT tokens for stateless authentication. Tokens expire after 24 hours.
Refresh tokens are stored in httpOnly cookies with a 30-day lifetime.

## Token Flow
1. User logs in with email/password
2. Server validates credentials against bcrypt hash
3. Server issues JWT (24h) + refresh token (30d)
4. Client stores JWT in memory, refresh token in cookie
5. On 401, client uses refresh token to get new JWT

## Security Considerations
- Refresh tokens are rotated on each use (one-time use)
- Token revocation via a blocklist in Redis (checked on each request)
- Rate limiting: 5 login attempts per minute per IP
- CSRF protection via SameSite=Strict on cookies
