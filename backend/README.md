# Embeddings Backend (FastAPI + pgvector)

Multimodal post embeddings with CLIP (text+image fused), Postgres vector storage, and simple ANN search.

## Endpoints
- `GET /healthz` – liveness
- `POST /api/posts` – multipart form: `title`, `body`, optional `image`
- `POST /api/search` – JSON: `{ "q": "...", "limit": 20 }`
- `POST /api/search-multipart` – multipart: `q`, optional `image`, `limit`

## Local (Docker Compose)
```bash
cp .env.example .env
docker compose up -d --build
curl http://localhost:8000/healthz
