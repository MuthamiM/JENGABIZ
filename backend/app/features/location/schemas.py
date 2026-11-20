from pydantic import BaseModel
from uuid import UUID
from typing import List

class LocationResponse(BaseModel):
    id: UUID
    county: str
    area: str
    estate: str

    class Config:
        from_attributes = True

class LocationHierarchy(BaseModel):
    county: str
    areas: List[str]
