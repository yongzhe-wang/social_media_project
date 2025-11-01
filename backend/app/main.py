# app/main.py
from fastapi import FastAPI, UploadFile, File, Form, BackgroundTasks, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import psycopg2.extras

from .settings import settings
from .db import conn, ensure_pgvector_extension
from .embeddings import cohere_embed
from .utils import clean_text
from .models import PostCreate, PostOut, SearchOut, SearchRequest, ErrorOut

app = FastAPI(title="Embeddings API")

# --- CORS ---
allow_origins = (
    [o.strip() for o in settings.CORS_ALLOW_ORIGINS.split(",")]
    if settings.CORS_ALLOW_ORIGINS != "*"
    else ["*"]
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=allow_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- Startup ---
@app.on_event("startup")
def _startup():
    ensure_pgvector_extension()

@app.get("/healthz")
def healthz():
    return {"ok": True}

# --- Create post ---
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

    with conn() as c, c.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(
            "INSERT INTO posts(title, body) VALUES(%s,%s) RETURNING id, title, body",
            (title, text),
        )
        row = cur.fetchone()

    bg.add_task(_compute_and_save_embedding, row["id"], text, img_bytes)
    return PostOut(id=row["id"], title=row["title"], body=row["body"])

def _compute_and_save_embedding(post_id: int, text: str, img_bytes: bytes | None):
    with conn() as c, c.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(
            "SELECT COALESCE(title,'') AS title, COALESCE(body,'') AS body "
            "FROM posts WHERE id=%s",
            (post_id,),
        )
        row = cur.fetchone()

    full_text = (row["title"] + " " + row["body"]).strip()
    e = cohere_embed(
        full_text,
        img_bytes,
        input_type="search_document",
        output_dimension=settings.COHERE_EMBED_DIM,
    )

    with conn() as c, c.cursor() as cur:
        cur.execute(
            """
            UPDATE posts
            SET embedding = (%s)::float4[]::vector,
                embedding_model = %s,
                embedding_version = %s
            WHERE id = %s
            """,
            (e, settings.COHERE_EMBED_MODEL, 1, post_id),
        )

# --- Search (text) ---
@app.post("/api/search", response_model=list[SearchOut], responses={400: {"model": ErrorOut}})
def search(req: SearchRequest):
    q_text = clean_text(req.q)
    if not q_text:
        raise HTTPException(status_code=400, detail="empty query")

    q_emb = cohere_embed(
        q_text,
        None,
        input_type="search_query",
        output_dimension=settings.COHERE_EMBED_DIM,
    )

    with conn() as c, c.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("SET LOCAL ivfflat.probes = %s", (10,))
        cur.execute(
            """
            SELECT id, title, body
            FROM posts
            WHERE embedding IS NOT NULL
            ORDER BY embedding <=> (%s)::float4[]::vector
            LIMIT %s
            """,
            (q_emb, min(max(req.limit, 1), 200)),
        )
        rows = cur.fetchall()
    return [SearchOut(**r) for r in rows]

# --- Search (multipart) ---
@app.post("/api/search-multipart", response_model=list[SearchOut], responses={400: {"model": ErrorOut}})
async def search_multipart(
    q: str = Form(""),
    image: UploadFile | None = File(None),
    limit: int = Form(20),
):
    text = clean_text(q)
    img_bytes = await image.read() if image else None
    if not text and not img_bytes:
        raise HTTPException(status_code=400, detail="empty query")

    q_emb = cohere_embed(
        text,
        img_bytes,
        input_type="search_query",
        output_dimension=settings.COHERE_EMBED_DIM,
    )

    with conn() as c, c.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("SET LOCAL ivfflat.probes = %s", (10,))
        cur.execute(
            """
            SELECT id, title, body
            FROM posts
            WHERE embedding IS NOT NULL
            ORDER BY embedding <=> (%s)::float4[]::vector
            LIMIT %s
            """,
            (q_emb, min(max(limit, 1), 200)),
        )
        rows = cur.fetchall()
    return [SearchOut(**r) for r in rows]

# --- Where am I ---
@app.get("/debug/whereami")
def whereami():
    with conn() as c, c.cursor() as cur:
        cur.execute("SELECT current_database(), inet_server_addr(), inet_server_port();")
        db, host, port = cur.fetchone()
        cur.execute("SELECT count(*) FROM posts;")
        total = cur.fetchone()[0]
        cur.execute("SELECT count(*) FROM posts WHERE embedding IS NOT NULL;")
        embedded = cur.fetchone()[0]
    return {
        "PG_DSN_in_process": settings.PG_DSN,
        "db": db,
        "server_addr": str(host),
        "server_port": port,
        "posts_total": total,
        "posts_with_embedding": embedded,
    }

# --- Search debug (single definition) ---
@app.post("/api/search-debug", response_model=list[dict], responses={400: {"model": ErrorOut}})
def search_debug(req: SearchRequest):
    q_text = clean_text(req.q)
    if not q_text:
        raise HTTPException(status_code=400, detail="empty query")

    q_emb = cohere_embed(
        q_text, None, input_type="search_query",
        output_dimension=settings.COHERE_EMBED_DIM
    )

    with conn() as c, c.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("SET LOCAL ivfflat.probes = %s", (10,))
        cur.execute(
            """
            SELECT id, title, body,
                   (embedding <=> (%s)::float4[]::vector) AS distance
            FROM posts
            WHERE embedding IS NOT NULL
            ORDER BY distance
            LIMIT %s
            """,
            (q_emb, min(max(req.limit, 1), 200)),
        )
        return cur.fetchall()

# --- Debug helpers ---
@app.get("/debug/posts")
def debug_posts():
    # No unsupported casts. Just show whether an embedding exists and its model tag.
    with conn() as c, c.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(
            """
            SELECT id, title, embedding_model, (embedding IS NOT NULL) AS has_embedding
            FROM posts
            ORDER BY id
            LIMIT 50
            """
        )
        return cur.fetchall()

@app.get("/debug/raw")
def debug_raw():
    with conn() as c, c.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(
            """
            SELECT id, title, (embedding IS NULL) AS embedding_is_null
            FROM posts
            ORDER BY id
            LIMIT 50
            """
        )
        return cur.fetchall()

@app.get("/debug/selfsim")
def debug_selfsim():
    # If pgvector is working, this returns self-distance 0 rows
    with conn() as c, c.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(
            """
            SELECT id, title, (embedding <=> embedding) AS d
            FROM posts
            WHERE embedding IS NOT NULL
            ORDER BY id
            LIMIT 50
            """
        )
        return cur.fetchall()

@app.post("/debug/q")
def debug_q(req: SearchRequest):
    q_text = clean_text(req.q)
    if not q_text:
        raise HTTPException(status_code=400, detail="empty query")
    q_emb = cohere_embed(
        q_text, None, input_type="search_query",
        output_dimension=settings.COHERE_EMBED_DIM
    )
    return {
        "len": len(q_emb),
        "head": q_emb[:6],
        "model": settings.COHERE_EMBED_MODEL,
        "dim_env": settings.COHERE_EMBED_DIM,
    }
