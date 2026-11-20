from sqlalchemy import Column, String, DateTime, ForeignKey, Numeric, JSON
from sqlalchemy.dialects.postgresql import UUID
import uuid
from datetime import datetime, timezone
from app.database import Base

class Sale(Base):
    __tablename__ = "sales"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    shop_id = Column(UUID(as_uuid=True), ForeignKey("shops.id"), nullable=False, index=True)
    customer_id = Column(UUID(as_uuid=True), ForeignKey("customers.id"), nullable=True, index=True)
    type = Column(String(20), nullable=False, default="cash")  # cash or credit
    total = Column(Numeric(10, 2), nullable=False)
    items = Column(JSON, nullable=False)  # [{item_id, name, qty, price}]
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
