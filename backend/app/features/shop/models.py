from sqlalchemy import Column, String, DateTime, Boolean, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
import uuid
from datetime import datetime, timezone
from app.database import Base

class Shop(Base):
    __tablename__ = "shops"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    owner_id = Column(UUID(as_uuid=True), nullable=False, index=True)
    name = Column(String(150), nullable=False)
    profile_type = Column(String(50), nullable=False, default="duka")  # duka or mama_mboga
    payment_number = Column(String(50), nullable=True)  # Till, Paybill, or Phone
    location_id = Column(UUID(as_uuid=True), ForeignKey("locations.id"), nullable=True)
    language = Column(String(10), default="sw")
    is_published = Column(Boolean, default=False)
    photo_url = Column(String(255), nullable=True)
    opening_hours = Column(String(100), nullable=True, default="6:00 AM - 9:00 PM")
    is_deleted = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))
