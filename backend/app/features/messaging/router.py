from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import List, Optional
from uuid import UUID

router = APIRouter(prefix="/messaging", tags=["Reminders & Receipts"])

class ReminderRequest(BaseModel):
    customer_phone: str
    customer_name: str
    amount_owed: float
    payment_number: str
    channel: str = "sms"  # sms or whatsapp

class ReceiptRequest(BaseModel):
    customer_phone: str
    items_summary: str
    total: float
    payment_number: str

@router.post("/send-reminder")
async def send_reminder(req: ReminderRequest):
    # Template: "Habari [Name], kumbukumbu ya deni lako la KSh [Amount] kwa [Duka]. Lipa kupitia [Payment Number]. Sent via Duka Ledger"
    message = (
        f"Habari {req.customer_name}, kumbukumbu ya deni lako la KSh {req.amount_owed:.2f}. "
        f"Tafadhali lipa kupitia: {req.payment_number}. Asante! Sent via Duka Ledger"
    )
    # Queue message in Celery / Africa's Talking
    return {"status": "queued", "channel": req.channel, "message_preview": message}

@router.post("/send-receipt")
async def send_receipt(req: ReceiptRequest):
    message = (
        f"Stakabadhi ya Duka Ledger: Jumla KSh {req.total:.2f}. {req.items_summary}. "
        f"Lipa: {req.payment_number}. Asante kwa kununua kwetu! Sent via Duka Ledger"
    )
    return {"status": "sent", "receipt": message}
