import os
import uuid
import secrets
from datetime import datetime, timedelta, timezone

import httpx
from fastapi import FastAPI, HTTPException, Header
from pydantic import BaseModel
from sqlalchemy import (
    create_engine,
    String,
    Float,
    DateTime,
    Boolean,
    Text,
    ForeignKey,
    UniqueConstraint,
)
from sqlalchemy.orm import (
    DeclarativeBase,
    Mapped,
    mapped_column,
    sessionmaker,
)
from jose import jwt
from google.oauth2 import id_token
from google.auth.transport import requests as google_requests


# ============================================================
# CONFIG
# ============================================================

APP_NAME = "AS COIN API"

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "sqlite:///./ascoin.db",
)

JWT_SECRET = os.getenv(
    "JWT_SECRET",
    "CHANGE_THIS_SECRET_BEFORE_PRODUCTION",
)

JWT_ALGORITHM = "HS256"
JWT_DAYS = 30

GOOGLE_CLIENT_ID = os.getenv(
    "GOOGLE_CLIENT_ID",
    "",
)

TELEGRAM_GATEWAY_TOKEN = os.getenv(
    "TELEGRAM_GATEWAY_TOKEN",
    "",
)

TRONGRID_API_KEY = os.getenv(
    "TRONGRID_API_KEY",
    "",
)

USDT_DEPOSIT_ADDRESS = os.getenv(
    "USDT_DEPOSIT_ADDRESS",
    "TYskeHD53kcs9ksb5ymBGubtJAJpQPkND2",
)

USDT_CONTRACT = os.getenv(
    "USDT_CONTRACT",
    "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t",
)

PACKAGE_USDT = 50.0
PACKAGE_ASC = 5000.0

KYC_USDT = 1.0

TRONGRID_URL = "https://api.trongrid.io"


# ============================================================
# DATABASE
# ============================================================

class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(
        String(64),
        primary_key=True,
    )

    phone: Mapped[str | None] = mapped_column(
        String(32),
        unique=True,
        nullable=True,
    )

    email: Mapped[str | None] = mapped_column(
        String(255),
        unique=True,
        nullable=True,
    )

    telegram_id: Mapped[str | None] = mapped_column(
        String(128),
        unique=True,
        nullable=True,
    )

    balance: Mapped[float] = mapped_column(
        Float,
        default=0.0,
    )

    kyc_status: Mapped[str] = mapped_column(
        String(32),
        default="Pending",
    )

    wallet_address: Mapped[str | None] = mapped_column(
        String(128),
        unique=True,
        nullable=True,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=lambda: datetime.now(timezone.utc),
    )


class OtpRequest(Base):
    __tablename__ = "otp_requests"

    id: Mapped[str] = mapped_column(
        String(64),
        primary_key=True,
    )

    phone: Mapped[str] = mapped_column(
        String(32),
        index=True,
    )

    telegram_request_id: Mapped[str | None] = mapped_column(
        String(128),
        nullable=True,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=lambda: datetime.now(timezone.utc),
    )

    expires_at: Mapped[datetime] = mapped_column(
        DateTime,
    )

    used: Mapped[bool] = mapped_column(
        Boolean,
        default=False,
    )


class Purchase(Base):
    __tablename__ = "purchases"

    id: Mapped[str] = mapped_column(
        String(64),
        primary_key=True,
    )

    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id"),
        index=True,
    )

    usdt: Mapped[float] = mapped_column(
        Float,
    )

    asc: Mapped[float] = mapped_column(
        Float,
    )

    status: Mapped[str] = mapped_column(
        String(32),
        default="Pending",
    )

    tx_hash: Mapped[str | None] = mapped_column(
        String(128),
        unique=True,
        nullable=True,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=lambda: datetime.now(timezone.utc),
    )

    verified_at: Mapped[datetime | None] = mapped_column(
        DateTime,
        nullable=True,
    )


class Transaction(Base):
    __tablename__ = "transactions"

    id: Mapped[str] = mapped_column(
        String(64),
        primary_key=True,
    )

    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id"),
        index=True,
    )

    tx_type: Mapped[str] = mapped_column(
        String(32),
    )

    amount: Mapped[float] = mapped_column(
        Float,
    )

    address: Mapped[str] = mapped_column(
        String(128),
    )

    status: Mapped[str] = mapped_column(
        String(32),
    )

    tx_hash: Mapped[str | None] = mapped_column(
        String(128),
        nullable=True,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=lambda: datetime.now(timezone.utc),
    )


class KycPayment(Base):
    __tablename__ = "kyc_payments"

    id: Mapped[str] = mapped_column(
        String(64),
        primary_key=True,
    )

    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id"),
        index=True,
    )

    amount: Mapped[float] = mapped_column(
        Float,
        default=1.0,
    )

    status: Mapped[str] = mapped_column(
        String(32),
        default="Pending",
    )

    tx_hash: Mapped[str | None] = mapped_column(
        String(128),
        unique=True,
        nullable=True,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=lambda: datetime.now(timezone.utc),
    )


# SQLite is fine for initial testing.
// Production should use PostgreSQL.
if DATABASE_URL.startswith("sqlite"):
    engine = create_engine(
        DATABASE_URL,
        connect_args={"check_same_thread": False},
    )
else:
    engine = create_engine(
        DATABASE_URL,
        pool_pre_ping=True,
    )

SessionLocal = sessionmaker(
    bind=engine,
    autoflush=False,
    autocommit=False,
)

Base.metadata.create_all(engine)


# ============================================================
# APP
# ============================================================

app = FastAPI(
    title=APP_NAME,
    version="1.0.0",
)


@app.get("/")
def root():
    return {
        "app": "AS COIN",
        "status": "online",
    }


@app.get("/health")
def health():
    return {
        "status": "ok",
    }


# ============================================================
# MODELS
# ============================================================

class PhoneOtpRequest(BaseModel):
    phone: str


class PhoneOtpVerify(BaseModel):
    phone: str
    otp: str


class GoogleLoginRequest(BaseModel):
    id_token: str


class TelegramLoginRequest(BaseModel):
    telegram_data: str


class SendAscRequest(BaseModel):
    address: str
    amount: float


# ============================================================
# HELPERS
# ============================================================

def now():
    return datetime.now(timezone.utc)


def create_token(user_id: str):
    payload = {
        "sub": user_id,
        "exp": now() + timedelta(days=JWT_DAYS),
    }

    return jwt.encode(
        payload,
        JWT_SECRET,
        algorithm=JWT_ALGORITHM,
    )


def get_user_from_token(
    authorization: str | None,
):
    if not authorization:
        raise HTTPException(
            status_code=401,
            detail="Authorization required.",
        )

    if not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=401,
            detail="Invalid authorization.",
        )

    token = authorization[7:]

    try:
        payload = jwt.decode(
            token,
            JWT_SECRET,
            algorithms=[JWT_ALGORITHM],
        )

        user_id = payload.get("sub")

        if not user_id:
            raise Exception()

    except Exception:
        raise HTTPException(
            status_code=401,
            detail="Invalid or expired session.",
        )

    db = SessionLocal()

    try:
        user = db.get(User, user_id)

        if not user:
            raise HTTPException(
                status_code=404,
                detail="User not found.",
            )

        return user
    finally:
        db.close()


def user_json(user: User, token: str | None = None):
    return {
        "token": token or "",
        "user_id": user.id,
        "phone": user.phone,
        "email": user.email,
        "telegram_id": user.telegram_id,
        "balance": user.balance,
        "kyc_status": user.kyc_status,
        "wallet_address": user.wallet_address,
    }


# ============================================================
# TELEGRAM GATEWAY OTP
# ============================================================

@app.post("/auth/request-otp")
async def request_otp(data: PhoneOtpRequest):

    phone = data.phone.strip()

    if not phone.startswith("+"):
        raise HTTPException(
            status_code=400,
            detail="Phone number must use international format.",
        )

    if not TELEGRAM_GATEWAY_TOKEN:
        raise HTTPException(
            status_code=503,
            detail="Telegram verification is not configured.",
        )

    request_id = str(uuid.uuid4())

    url = (
        "https://gatewayapi.telegram.org/"
        "sendVerificationMessage"
    )

    headers = {
        "Authorization": (
            f"Bearer {TELEGRAM_GATEWAY_TOKEN}"
        ),
        "Content-Type": "application/json",
    }

    body = {
        "phone_number": phone,
        "code_length": 6,
        "ttl": 300,
        "payload": request_id,
    }

    async with httpx.AsyncClient(timeout=20) as client:
        response = await client.post(
            url,
            headers=headers,
            json=body,
        )

    result = response.json()

    if not result.get("ok"):
        raise HTTPException(
            status_code=400,
            detail=result.get(
                "error",
                "Telegram verification failed.",
            ),
        )

    telegram_request_id = (
        result.get("result", {})
        .get("request_id")
    )

    if not telegram_request_id:
        raise HTTPException(
            status_code=500,
            detail="Telegram did not return a request ID.",
        )

    db = SessionLocal()

    try:
        record = OtpRequest(
            id=request_id,
            phone=phone,
            telegram_request_id=str(
                telegram_request_id
            ),
            created_at=now(),
            expires_at=now() + timedelta(minutes=5),
        )

        db.add(record)
        db.commit()

    finally:
        db.close()

    return {
        "message": "Verification code sent via Telegram.",
    }


@app.post("/auth/verify-otp")
async def verify_otp(data: PhoneOtpVerify):

    phone = data.phone.strip()
    otp = data.otp.strip()

    db = SessionLocal()

    try:
        record = (
            db.query(OtpRequest)
            .filter(
                OtpRequest.phone == phone,
                OtpRequest.used == False,
            )
            .order_by(
                OtpRequest.created_at.desc()
            )
            .first()
        )

        if not record:
            raise HTTPException(
                status_code=400,
                detail="Verification request not found.",
            )

        if record.expires_at < now():
            raise HTTPException(
                status_code=400,
                detail="Verification code expired.",
            )

        if not record.telegram_request_id:
            raise HTTPException(
                status_code=400,
                detail="Invalid verification request.",
            )

    finally:
        db.close()

    if not TELEGRAM_GATEWAY_TOKEN:
        raise HTTPException(
            status_code=503,
            detail="Telegram verification is not configured.",
        )

    url = (
        "https://gatewayapi.telegram.org/"
        "checkVerificationStatus"
    )

    headers = {
        "Authorization": (
            f"Bearer {TELEGRAM_GATEWAY_TOKEN}"
        ),
        "Content-Type": "application/json",
    }

    body = {
        "request_id": record.telegram_request_id,
        "code": otp,
    }

    async with httpx.AsyncClient(timeout=20) as client:
        response = await client.post(
            url,
            headers=headers,
            json=body,
        )

    result = response.json()

    if not result.get("ok"):
        raise HTTPException(
            status_code=400,
            detail=result.get(
                "error",
                "Verification failed.",
            ),
        )

    verification = (
        result.get("result", {})
        .get("verification_status", {})
    )

    if verification.get("status") != "code_valid":
        raise HTTPException(
            status_code=400,
            detail="Invalid verification code.",
        )

    db = SessionLocal()

    try:
        record = db.get(
            OtpRequest,
            record.id,
        )

        if not record or record.used:
            raise HTTPException(
                status_code=400,
                detail="Verification request already used.",
            )

        record.used = True

        user = (
            db.query(User)
            .filter(User.phone == phone)
            .first()
        )

        # One phone number = one account.
        if not user:
            user = User(
                id=secrets.token_hex(16),
                phone=phone,
                balance=0.0,
                kyc_status="Pending",
            )

            db.add(user)
            db.flush()

        token = create_token(user.id)

        db.commit()

        return user_json(
            user,
            token,
        )

    finally:
        db.close()


# ============================================================
# GOOGLE LOGIN
# ============================================================

@app.post("/auth/google")
async def google_login(data: GoogleLoginRequest):

    if not GOOGLE_CLIENT_ID:
        raise HTTPException(
            status_code=503,
            detail="Google authentication is not configured.",
        )

    try:
        info = id_token.verify_oauth2_token(
            data.id_token,
            google_requests.Request(),
            GOOGLE_CLIENT_ID,
        )

    except Exception:
        raise HTTPException(
            status_code=401,
            detail="Invalid Google authentication.",
        )

    email = info.get("email")

    if not email:
        raise HTTPException(
            status_code=400,
            detail="Google account email is unavailable.",
        )

    db = SessionLocal()

    try:
        user = (
            db.query(User)
            .filter(User.email == email)
            .first()
        )

        if not user:
            user = User(
                id=secrets.token_hex(16),
                email=email,
                balance=0.0,
                kyc_status="Pending",
            )

            db.add(user)
            db.flush()

        token = create_token(user.id)

        db.commit()

        return user_json(
            user,
            token,
        )

    finally:
        db.close()


# ============================================================
# TELEGRAM LOGIN
# ============================================================

@app.post("/auth/telegram")
async def telegram_login(
    data: TelegramLoginRequest,
):
    # Telegram Gateway verification is the primary
    # phone-verification route.
    #
    # A full Telegram Login Widget / OAuth flow should
    # verify Telegram's signed authentication payload
    # before accepting telegram_data.
    #
    # Do NOT trust arbitrary client-supplied telegram IDs.

    raise HTTPException(
        status_code=501,
        detail=(
            "Use Telegram phone verification first. "
            "Telegram Login Widget verification must be "
            "configured before this endpoint is enabled."
        ),
    )


# ============================================================
# CURRENT USER
# ============================================================

@app.get("/me")
def me(
    authorization: str | None = Header(default=None),
):
    user = get_user_from_token(
        authorization
    )

    return user_json(user)


# ============================================================
# KYC
# ============================================================

@app.post("/kyc/payment")
def create_kyc_payment(
    authorization: str | None = Header(default=None),
):
    user = get_user_from_token(
        authorization
    )

    db = SessionLocal()

    try:
        existing = (
            db.query(KycPayment)
            .filter(
                KycPayment.user_id == user.id,
                KycPayment.status == "Pending",
            )
            .first()
        )

        if existing:
            payment_id = existing.id
        else:
            payment_id = secrets.token_hex(16)

            payment = KycPayment(
                id=payment_id,
                user_id=user.id,
                amount=KYC_USDT,
                status="Pending",
            )

            db.add(payment)
            db.commit()

        return {
            "payment_id": payment_id,
            "amount_usdt": KYC_USDT,
            "network": "TRC20 (TRON)",
            "deposit_address": USDT_DEPOSIT_ADDRESS,
            "status": "Pending",
        }

    finally:
        db.close()


@app.get("/kyc/status")
def kyc_status(
    authorization: str | None = Header(default=None),
):
    user = get_user_from_token(
        authorization
    )

    return {
        "status": user.kyc_status,
    }


# ============================================================
# PURCHASE
# ============================================================

@app.post("/purchases/create")
def create_purchase(
    authorization: str | None = Header(default=None),
):
    user = get_user_from_token(
        authorization
    )

    if user.kyc_status.lower() != "verified":
        raise HTTPException(
            status_code=403,
            detail="KYC verification is required before purchase.",
        )

    db = SessionLocal()

    try:
        purchase = Purchase(
            id=secrets.token_hex(16),
            user_id=user.id,
            usdt=PACKAGE_USDT,
            asc=PACKAGE_ASC,
            status="Pending",
        )

        db.add(purchase)
        db.commit()

        return {
            "id": purchase.id,
            "usdt": PACKAGE_USDT,
            "asc": PACKAGE_ASC,
            "status": "Pending",
            "network": "TRC20 (TRON)",
            "deposit_address": USDT_DEPOSIT_ADDRESS,
        }

    finally:
        db.close()


# ============================================================
# TRON / USDT VERIFICATION
# ============================================================

async def get_usdt_transfers():
    url = (
        f"{TRONGRID_URL}/v1/accounts/"
        f"{USDT_DEPOSIT_ADDRESS}/transactions/trc20"
    )

    headers = {}

    if TRONGRID_API_KEY:
        headers["TRON-PRO-API-KEY"] = TRONGRID_API_KEY

    params = {
        "only_confirmed": "true",
        "limit": "200",
        "contract_address": USDT_CONTRACT,
    }

    async with httpx.AsyncClient(timeout=20) as client:
        response = await client.get(
            url,
            headers=headers,
            params=params,
        )

    if response.status_code != 200:
        return []

    data = response.json()

    return data.get("data", [])


async def verify_purchase_on_chain(
    purchase: Purchase,
):
    transfers = await get_usdt_transfers()

    for tx in transfers:
        tx_hash = (
            tx.get("transaction_id")
            or tx.get("transactionId")
        )

        if not tx_hash:
            continue

        to_address = tx.get("to")

        if to_address != USDT_DEPOSIT_ADDRESS:
            continue

        token = tx.get("token_info", {})
        contract = token.get("address")

        if contract != USDT_CONTRACT:
            continue

        decimals = int(
            token.get("decimals", 6)
        )

        raw_value = tx.get("value", "0")

        try:
            amount = (
                float(raw_value)
                / (10 ** decimals)
            )
        except Exception:
            continue

        if amount < purchase.usdt:
            continue

        return tx_hash

    return None


@app.get("/purchases/{purchase_id}")
async def purchase_status(
    purchase_id: str,
    authorization: str | None = Header(default=None),
):
    user = get_user_from_token(
        authorization
    )

    db = SessionLocal()

    try:
        purchase = db.get(
            Purchase,
            purchase_id,
        )

        if not purchase:
            raise HTTPException(
                status_code=404,
                detail="Purchase not found.",
            )

        if purchase.user_id != user.id:
            raise HTTPException(
                status_code=403,
                detail="Access denied.",
            )

        if purchase.status == "Pending":

            tx_hash = await verify_purchase_on_chain(
                purchase
            )

            if tx_hash:

                # Unique transaction hash prevents
                # double-crediting the same blockchain
                # payment.
                already_used = (
                    db.query(Purchase)
                    .filter(
                        Purchase.tx_hash == tx_hash
                    )
                    .first()
                )

                if not already_used:

                    purchase.tx_hash = tx_hash
                    purchase.status = "Confirmed"
                    purchase.verified_at = now()

                    user.balance += purchase.asc

                    transaction = Transaction(
                        id=secrets.token_hex(16),
                        user_id=user.id,
                        tx_type="Purchase",
                        amount=purchase.asc,
                        address=USDT_DEPOSIT_ADDRESS,
                        status="Confirmed",
                        tx_hash=tx_hash,
                    )

                    db.add(transaction)
                    db.commit()

        return {
            "id": purchase.id,
            "usdt": purchase.usdt,
            "asc": purchase.asc,
            "status": purchase.status,
            "tx_hash": purchase.tx_hash,
            "created_at": purchase.created_at.isoformat(),
        }

    finally:
        db.close()


# ============================================================
# TRANSACTIONS
# ============================================================

@app.get("/transactions")
def transactions(
    authorization: str | None = Header(default=None),
):
    user = get_user_from_token(
        authorization
    )

    db = SessionLocal()

    try:
        rows = (
            db.query(Transaction)
            .filter(
                Transaction.user_id == user.id
            )
            .order_by(
                Transaction.created_at.desc()
            )
            .all()
        )

        return {
            "transactions": [
                {
                    "id": x.id,
                    "type": x.tx_type,
                    "amount": x.amount,
                    "address": x.address,
                    "status": x.status,
                    "tx_hash": x.tx_hash,
                    "created_at": x.created_at.isoformat(),
                }
                for x in rows
            ]
        }

    finally:
        db.close()


# ============================================================
# ASC SEND
# ============================================================

@app.post("/wallet/send")
def send_asc(
    data: SendAscRequest,
    authorization: str | None = Header(default=None),
):
    user = get_user_from_token(
        authorization
    )

    if data.amount <= 0:
        raise HTTPException(
            status_code=400,
            detail="Invalid ASC amount.",
        )

    if not data.address.strip():
        raise HTTPException(
            status_code=400,
            detail="Recipient address is required.",
        )

    db = SessionLocal()

    try:
        user = db.get(User, user.id)

        if user.balance < data.amount:
            raise HTTPException(
                status_code=400,
                detail="Insufficient ASC balance.",
            )

        # IMPORTANT:
        # Internal ledger transfer is intentionally not
        # treated as a blockchain transfer.
        #
        # Real on-chain ASC transfer requires:
        # 1. deployed ASC token contract
        # 2. controlled signing wallet
        # 3. private key stored only as server secret
        # 4. TRON transaction signing/broadcasting
        #
        # Until those are configured, do NOT deduct the
        # user's balance pretending a blockchain transfer
        # happened.

        raise HTTPException(
            status_code=503,
            detail=(
                "ASC blockchain transfer is not configured yet. "
                "No balance was deducted."
            ),
        )

    finally:
        db.close()
