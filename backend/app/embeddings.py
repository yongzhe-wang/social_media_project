import io
from typing import Optional

import torch
import open_clip
from PIL import Image
from .settings import settings

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"

# load once at import time
model, _, preprocess = open_clip.create_model_and_transforms(
    settings.MODEL_NAME, pretrained=settings.MODEL_PRETRAINED, device=DEVICE
)
tokenizer = open_clip.get_tokenizer(settings.MODEL_NAME)

@torch.inference_mode()
def fuse_embed(text: str, image_bytes: Optional[bytes]) -> list[float]:
    # Encode text (optional)
    if text:
        tok = tokenizer([text]).to(DEVICE)
        e_t = model.encode_text(tok)
        e_t = torch.nn.functional.normalize(e_t, dim=-1)
    else:
        e_t = None

    # Encode image (optional)
    if image_bytes:
        img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        img = preprocess(img).unsqueeze(0).to(DEVICE)
        e_i = model.encode_image(img)
        e_i = torch.nn.functional.normalize(e_i, dim=-1)
    else:
        e_i = None

    if e_t is not None and e_i is not None:
        v = torch.nn.functional.normalize(settings.FUSE_ALPHA * e_t + (1 - settings.FUSE_ALPHA) * e_i, dim=-1)
    elif e_t is not None:
        v = e_t
    elif e_i is not None:
        v = e_i
    else:
        # should not happen; caller ensures at least one signal
        raise ValueError("Both text and image are empty")

    return v.squeeze(0).detach().cpu().float().tolist()  # length = settings.EMBEDDING_DIM
