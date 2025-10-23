import os

class Settings:
    PG_DSN: str = os.environ.get(
        "PG_DSN",
        "postgres://app:secret@postgres:5432/app",
    )
    CORS_ALLOW_ORIGINS: str = os.environ.get("CORS_ALLOW_ORIGINS", "*")
    MODEL_NAME: str = os.environ.get("MODEL_NAME", "ViT-B-32")
    MODEL_PRETRAINED: str = os.environ.get("MODEL_PRETRAINED", "openai")
    FUSE_ALPHA: float = float(os.environ.get("FUSE_ALPHA", "0.5"))
    EMBEDDING_DIM: int = int(os.environ.get("EMBEDDING_DIM", "512"))
    MAX_IMAGE_BYTES: int = int(os.environ.get("MAX_IMAGE_BYTES", str(10 * 1024 * 1024)))  # 10MB

settings = Settings()
