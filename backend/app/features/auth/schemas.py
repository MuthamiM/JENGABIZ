from pydantic import BaseModel, Field

class RequestOtpRequest(BaseModel):
    phone: str = Field(..., example="+254712345678")

class VerifyOtpRequest(BaseModel):
    phone: str = Field(..., example="+254712345678")
    otp_code: str = Field(..., example="123456")

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: str
    phone: str
