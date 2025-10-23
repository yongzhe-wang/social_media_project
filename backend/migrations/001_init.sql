CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS posts (
  id SERIAL PRIMARY KEY,
  title TEXT NOT NULL,
  body TEXT,
  embedding vector(512),
  embedding_model TEXT DEFAULT 'ViT-B-32',
  embedding_version INT DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ANN index (tune lists later)
CREATE INDEX IF NOT EXISTS posts_embedding_idx
  ON posts USING ivfflat (embedding vector_l2_ops) WITH (lists = 100);
