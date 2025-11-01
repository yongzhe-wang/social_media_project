CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS posts (
  id SERIAL PRIMARY KEY,
  title TEXT NOT NULL,
  body TEXT,
  embedding vector(1536),
  embedding_model TEXT DEFAULT 'embed-v4.0',
  embedding_version INT DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ANN index for cosine
CREATE INDEX IF NOT EXISTS posts_embedding_idx
  ON posts USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
