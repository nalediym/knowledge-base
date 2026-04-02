# API Guidelines

## Authentication
All API endpoints require a valid JWT in the Authorization header.
Tokens are issued by the auth service and expire after 24 hours.
Use refresh tokens to obtain new JWTs without re-authenticating.

## Rate Limiting
- Public endpoints: 100 requests/minute per IP
- Authenticated endpoints: 1000 requests/minute per user
- Auth endpoints: 5 requests/minute per IP (login, register, refresh)

## Error Format
All errors return JSON:
```json
{
  "error": "human_readable_message",
  "code": "MACHINE_CODE",
  "details": {}
}
```

## Versioning
API is versioned via URL path: `/api/v1/`, `/api/v2/`.
Breaking changes require a new version. Additive changes are allowed in-place.
