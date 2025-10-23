from pydantic import BaseModel, Field
from typing import Optional, List

class PostCreate(BaseModel):
    title: str = Field(min_length=1)
    body: Optional[str] = ""

class PostOut(BaseModel):
    id: int
    title: str
    body: str | None = None

class SearchOut(BaseModel):
    id: int
    title: str
    body: str | None = None

class SearchRequest(BaseModel):
    q: str
    limit: int = 20

class ErrorOut(BaseModel):
    detail: str

class BatchCreateOut(BaseModel):
    inserted_ids: List[int]
