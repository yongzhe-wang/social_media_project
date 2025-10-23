import psycopg2, psycopg2.extras
from .settings import settings

def conn():
    return psycopg2.connect(settings.PG_DSN)

def ensure_pgvector_extension():
    with conn() as c, c.cursor() as cur:
        cur.execute("CREATE EXTENSION IF NOT EXISTS vector;")
