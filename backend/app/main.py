from fastapi import FastAPI, UploadFile, File, Form, BackgroundTasks, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import psycopg2.extras

from .settings import settings
from .db import conn, ensure_pgvector_extension
from .embeddings import fuse_embed
from .utils import clean_text
from .models import PostCreate, PostOut, SearchOut, SearchRequest, ErrorOut

app = FastAPI(
    title="Embeddings Backend",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[o.strip() for o in settings.CORS_ALLOW_ORIGINS.split(",") if o.strip()],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Ensure pgvector once on startup
@app.on_event("startup")
def _startup():
    ensure_pgvector_extension()

@app.get("/healthz", response_model=dict)
def healthz():
    return {"ok": True}

@app.post("/api/posts", response_model=PostOut, responses={400: {"model": ErrorOut}})
async def create_post(
    bg: BackgroundTasks,
    title: str = Form(...),
    body: str = Form(""),
    image: UploadFile | None = File(None),
):
    text = clean_text(body or "")
    img_bytes = None
    if image:
        data = await image.read()
        if len(data) > settings.MAX_IMAGE_BYTES:
            raise HTTPException(status_code=400, detail="image too large")
        img_bytes = data

    # 1) create post row
    with conn() as c, c.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("INSERT INTO posts(title, body) VALUES(%s,%s) RETURNING id, title, body", (title, text))
        row = cur.fetchone()

    # 2) compute + save embedding in background
    bg.add_task(_compute_and_save_embedding, row["id"], text, img_bytes)

    return PostOut(id=row["id"], title=row["title"], body=row["body"])

def _compute_and_save_embedding(post_id: int, text: str, img_bytes: bytes | None):
    e = fuse_embed(text, img_bytes)  # list[float]
    with conn() as c, c.cursor() as cur:
        cur.execute(
            """
            UPDATE posts
            SET embedding = %s, embedding_model=%s, embedding_version=%s
            WHERE id = %s
            """,
            (e, settings.MODEL_NAME, 1, post_id),
        )

@app.post("/api/search", response_model=list[SearchOut], responses={400: {"model": ErrorOut}})
def search(req: SearchRequest):
    q_text = clean_text(req.q)
    if not q_text:
        raise HTTPException(status_code=400, detail="empty query")

    q_emb = fuse_embed(q_text, None)
    with conn() as c, c.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        # optional: control recall/latency
        cur.execute("SET LOCAL ivfflat.probes = %s", (10,))
        cur.execute(
            "SELECT id, title, body FROM posts ORDER BY embedding <-> %s LIMIT %s",
            (q_emb, min(max(req.limit, 1), 200)),
        )
        rows = cur.fetchall()
    return [SearchOut(**r) for r in rows]

# Optional multipart search (text + image)
@app.post("/api/search-multipart", response_model=list[SearchOut]])
async def search_multipart(
    q: str = Form(""),
    image: UploadFile | None = File(None),
    limit: int = Form(20),
):
    text = clean_text(q)
    img_bytes = await image.read() if image else None
    if not text and not img_bytes:
        raise HTTPException(status_code=400, detail="empty query")

    q_emb = fuse_embed(text, img_bytes)
    with conn() as c, c.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("SET LOCAL ivfflat.probes = %s", (10,))
        cur.execute(
            "SELECT id, title, body FROM posts ORDER BY embedding <-> %s LIMIT %s",
            (q_emb, min(max(limit, 1), 200)),
        )
        rows = cur.fetchall()
    return [SearchOut(**r) for r in rows]
