from enum import Enum

class ProfileType(str, Enum):
    DUKA = "duka"
    MAMA_MBOGA = "mama_mboga"

class PaymentMethod(str, Enum):
    CASH = "cash"
    MPESA = "mpesa"

class SaleType(str, Enum):
    CASH = "cash"
    CREDIT = "credit"

class StockMovementType(str, Enum):
    SALE = "sale"
    RESTOCK = "restock"
    DAMAGE = "damage"
    RETURN = "return"
    ADJUSTMENT = "adjustment"

class Language(str, Enum):
    SWAHILI = "sw"
    ENGLISH = "en"
