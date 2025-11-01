import base64
import io
from typing import Optional, Literal, List

import httpx
from PIL import Image

from .settings import settings

COHERE_BASE = "https://api.cohere.com/v2"

def _to_data_uri(img_bytes: bytes) -> str:
    # Normalize to PNG to be safe
    img = Image.open(io.BytesIO(img_bytes)).convert("RGB")
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    b64 = base64.b64encode(buf.getvalue()).decode("ascii")
    return f"data:image/png;base64,{b64}"

def cohere_embed(
    text: str,
    image_bytes: Optional[bytes],
    input_type: Literal["search_document","search_query","classification","clustering"]="search_document",
    output_dimension: Optional[int] = None,
) -> List[float]:
    if not settings.COHERE_API_KEY:
        raise RuntimeError("COHERE_API_KEY missing")

    content = []
    if text:
        content.append({"type":"text","text":text})
    if image_bytes:
        content.append({"type":"image","image": _to_data_uri(image_bytes)})

    if not content:
        raise ValueError("empty input for embedding")

    payload = {
        "inputs": [{"content": content}],
        "model": settings.COHERE_EMBED_MODEL,
        "input_type": input_type,
        "embedding_types": ["float"],
    }
    if output_dimension:
        payload["output_dimension"] = output_dimension

    headers = {"Authorization": f"Bearer {settings.COHERE_API_KEY}"}
    with httpx.Client(timeout=settings.COHERE_TIMEOUT) as client:
        r = client.post(f"{COHERE_BASE}/embed", json=payload, headers=headers)
    r.raise_for_status()
    data = r.json()
    return data["embeddings"]["float"][0]  # 1 input → 1 vector
