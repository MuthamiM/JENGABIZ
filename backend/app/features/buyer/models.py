from sqlalchemy import Column, String, DateTime, ForeignKey, Integer, Text
from sqlalchemy.dialects.postgresql import UUID
import uuid
from datetime import datetime, timezone
from app.database import Base

class PreOrder(Base):
    __tablename__ = "pre_orders"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    shop_id = Column(UUID(as_uuid=True), ForeignKey("shops.id"), nullable=False, index=True)
    buyer_name = Column(String(100), nullable=False)
    buyer_phone = Column(String(20), nullable=False)
    items_summary = Column(Text, nullable=False)  # e.g., "Kilo 2 za Nyanya, Vitunguu fungu 3"
    pickup_time = Column(String(50), default="Asubuhi (Morning)")
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

class CommunityNotice(Base):
    __tablename__ = "community_notices"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    location_id = Column(UUID(as_uuid=True), ForeignKey("locations.id"), nullable=False, index=True)
    title = Column(String(150), nullable=False)
    message = Column(Text, nullable=False)
    category = Column(String(50), default="general")  # water_outage, market_day, general
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
