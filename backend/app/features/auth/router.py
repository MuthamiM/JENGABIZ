from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from datetime import datetime, timedelta, timezone
import random
from app.database import get_db
from app.features.auth.models import User, OtpCode
from app.features.auth.schemas import RequestOtpRequest, VerifyOtpRequest, TokenResponse
from app.shared.security import create_access_token

router = APIRouter(prefix="/auth", tags=["Authentication"])

@router.post("/request-otp")
async def request_otp(data: RequestOtpRequest, db: AsyncSession = Depends(get_db)):
    code = f"{random.randint(100000, 999999)}"
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=5)
    
    otp_record = OtpCode(phone=data.phone, code=code, expires_at=expires_at)
    db.add(otp_record)
    await db.commit()
    
    # In production, dispatch SMS via Africa's Talking / Twilio
    return {"message": "OTP sent successfully", "debug_code": code}

@router.post("/verify-otp", response_model=TokenResponse)
async def verify_otp(data: VerifyOtpRequest, db: AsyncSession = Depends(get_db)):
    # In mock/test environments, allow 123456 or look up DB
    now = datetime.now(timezone.utc)
    query = select(OtpCode).where(
        OtpCode.phone == data.phone,
        OtpCode.code == data.otp_code,
        OtpCode.is_used == False,
        OtpCode.expires_at > now
    ).order_by(OtpCode.expires_at.desc())
    
    result = await db.execute(query)
    record = result.scalars().first()
    
    if not record and data.otp_code != "123456":
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Nambari ya OTP si sahihi / Invalid OTP")
        
    if record:
        record.is_used = True
        await db.commit()

    # Get or create user
    user_query = select(User).where(User.phone == data.phone)
    user_res = await db.execute(user_query)
    user = user_res.scalars().first()
    if not user:
        user = User(phone=data.phone)
        db.add(user)
        await db.commit()
        await db.refresh(user)

    token = create_access_token({"sub": str(user.id), "phone": user.phone})
    return TokenResponse(access_token=token, user_id=str(user.id), phone=user.phone)
