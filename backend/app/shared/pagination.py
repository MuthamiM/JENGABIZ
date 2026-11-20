from typing import Generic, TypeVar, List, Optional
from pydantic import BaseModel
from datetime import datetime

T = TypeVar("T")

class CursorPage(BaseModel, Generic[T]):
    items: List[T]
    next_cursor: Optional[str] = None
    has_more: bool = False
    total_count: Optional[int] = None
