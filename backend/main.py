import os
import secrets
from datetime import datetime, timedelta, timezone
from typing import Optional

import httpx
from fastapi import FastAPI, Depends, HTTPException, Header
from pydantic import BaseModel, Field
from jose import jwt, JWTError
from sqlalchemy import (
    create_engine,
    String,
    Float,
    Boolean,
    DateTime,
    Text,
    ForeignKey,
)
from sqlalchemy.orm import (
    DeclarativeBase,
    Mapped,
    mapped_column,
    sessionmaker,
    Session,
)

APP_NAME = "AS COIN"

JWT_SECRET = os.getenv("JWT_SECRET")
if not JWT_SECRET:
    JWT_SECRET = secrets.token_urlsafe(48)

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "sqlite:///./ascoin.db",
)

GOOGLE_CLIENT_ID = os.getenv(
    "GOOGLE_CLIENT_ID",
    "",
)

TELEGRAM_GATEWAY_TOKEN = os.getenv(
    "TELEGRAM_GATEWAY_TOKEN",
    "",
)

USDT_TRON_ADDRESS = os.getenv(
    "USDT_TRON_ADDRESS",
    "",
)

TRON_API_KEY = os.getenv(
    "TRON_API_KEY",
    "",
)

TRON_USDT_CONTRACT = os.getenv(
    "TRON_USDT_CONTRACT",
    "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t",
)

PACKAGE_USDT = 50.0
PACKAGE_ASC = 5000.0

KYC_FEE_USDT = 1.0

MAX_SUPPLY = 21_000_000.0


# ============================================================
# DATABASE
# ============================================================

connect_args = {}

if DATABASE_URL.startswith("sqlite"):
    connect_args = {
        "check_same_thread": False
    }

engine = create_engine(
    DATABASE_URL,
    connect_args=connect_args,
)

SessionLocal = sessionmaker(
    bind=engine,
    autoflush=False,
    autocommit=False,
)


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(
        primary_key=True
    )

    phone: Mapped[Optional[str]] = mapped_column(
        String(32),
        unique=True,
        index=True,
        nullable=True,
    )

    google_sub: Mapped[Optional[str]] = mapped_column(
        String(255),
        unique=True,
        index=True,
        nullable=True,
    )

    telegram_user_id: Mapped[Optional[str]] = mapped_column(
        String(255),
        unique=True,
        index=True,
        nullable=True,
    )

    balance: Mapped[float] = mapped_column(
        Float,
        default=0.0,
    )

    kyc_status: Mapped[str] = mapped_column(
        String(32),
        default="pending",
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
    )


class Otp(Base):
    __tablename__ = "otps"

    id: Mapped[int] = mapped_column(
        primary_key=True
    )

    phone: Mapped[str] = mapped_column(
        String(32),
        index=True,
    )

    code_hash: Mapped[str] = mapped_column(
        String(128)
    )

    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True)
    )

    attempts: Mapped[int] = mapped_column(
        default=0
    )

    used: Mapped[bool] = mapped_column(
        Boolean,
        default=False,
    )


class Purchase(Base):
    __tablename__ = "purchases"

    id: Mapped[int] = mapped_column(
        primary_key=True
    )

    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id"),
        index=True,
    )

    amount_usdt: Mapped[float] = mapped_column(
        Float,
        default=PACKAGE_USDT,
    )

    amount_asc: Mapped[float] = mapped_column(
        Float,
        default=PACKAGE_ASC,
    )

    deposit_address: Mapped[str] = mapped_column(
        String(64)
    )

    status: Mapped[str] = mapped_column(
        String(32),
        default="pending",
    )

    txid: Mapped[Optional[str]] = mapped_column(
        String(128),
        unique=True,
        nullable=True,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
    )

    confirmed_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )


class KycPayment(Base):
    __tablename__ = "kyc_payments"

    id: Mapped[int] = mapped_column(
        primary_key=True
    )

    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id"),
        index=True,
    )

    amount_usdt: Mapped[float] = mapped_column(
        Float,
        default=KYC_FEE_USDT,
    )

    deposit_address: Mapped[str] = mapped_column(
        String(64)
    )

    status: Mapped[str] = mapped_column(
        String(32),
        default="pending",
    )

    txid: Mapped[Optional[str]] = mapped_column(
        String(128),
        unique=True,
        nullable=True,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
    )

    confirmed_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )


class Ledger(Base):
    __tablename__ = "ledger"

    id: Mapped[int] = mapped_column(
        primary_key=True
    )

    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id"),
        index=True,
    )

    kind: Mapped[str] = mapped_column(
        String(32)
    )

    amount: Mapped[float] = mapped_column(
        Float
    )

    reference: Mapped[str] = mapped_column(
        String(128),
        unique=True,
    )

    note: Mapped[str] = mapped_column(
        Text,
        default="",
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
    )


class WalletTransaction(Base):
    __tablename__ = "wallet_transactions"

    id: Mapped[int] = mapped_column(
        primary_key=True
    )

    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id"),
        index=True,
    )

    kind: Mapped[str] = mapped_column(
        String(32)
    )

    amount: Mapped[float] = mapped_column(
        Float
    )

    address: Mapped[str] = mapped_column(
        String(128)
    )

    status: Mapped[str] = mapped_column(
        String(32),
        default="pending",
    )

    txid: Mapped[Optional[str]] = mapped_column(
        String(128),
        nullable=True,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
    )


Base.metadata.create_all(engine)


# ============================================================
# FASTAPI
# ============================================================

app = FastAPI(
    title=APP_NAME,
    version="1.0.0",
)


# ============================================================
# REQUEST MODELS
# ============================================================

class PhoneRequest(BaseModel):
    phone: str = Field(
        min_length=8,
        max_length=32,
    )


class OtpVerify(BaseModel):
    phone: str
    code: str = Field(
        min_length=4,
        max_length=8,
    )


class GoogleRequest(BaseModel):
    id_token: str = Field(
        min_length=20
    )


class TelegramRequest(BaseModel):
    phone: str = Field(
        min_length=8,
        max_length=32,
    )


class SendRequest(BaseModel):
    address: str = Field(
        min_length=20,
        max_length=128,
    )

    amount: float = Field(
        gt=0
    )


# ============================================================
# HELPERS
# ============================================================

def db_dep():
    db = SessionLocal()

    try:
        yield db
    finally:
        db.close()


def now():
    return datetime.now(timezone.utc)


def token_for(user: User) -> str:
    payload = {
        "sub": str(user.id),
        "exp": now() + timedelta(days=30),
    }

    return jwt.encode(
        payload,
        JWT_SECRET,
        algorithm="HS256",
    )


def normalize_phone(phone: str) -> str:
    phone = (
        phone
        .strip()
        .replace(" ", "")
        .replace("-", "")
    )

    if not phone.startswith("+"):
        raise HTTPException(
            400,
            "Phone must use international format, for example +91XXXXXXXXXX",
        )

    return phone


def make_otp_hash(code: str) -> str:
    import hashlib

    return hashlib.sha256(
        (code + JWT_SECRET).encode()
    ).hexdigest()


def verify_otp_hash(
    code: str,
    stored: str,
) -> bool:

    return secrets.compare_digest(
        make_otp_hash(code),
        stored,
    )


def serialize_user(user: User):

    return {
        "id": user.id,
        "phone": user.phone,
        "balance": user.balance,
        "kyc_status": user.kyc_status,
        "created_at": user.created_at.isoformat(),
    }


def current_user(
    authorization: Optional[str] = Header(
        default=None
    ),
    db: Session = Depends(db_dep),
):

    if (
        not authorization
        or not authorization.lower().startswith("bearer ")
    ):
        raise HTTPException(
            401,
            "Authentication required",
        )

    token = authorization.split(
        " ",
        1,
    )[1]

    try:

        payload = jwt.decode(
            token,
            JWT_SECRET,
            algorithms=["HS256"],
        )

        uid = int(
            payload["sub"]
        )

    except (
        JWTError,
        KeyError,
        ValueError,
    ):

        raise HTTPException(
            401,
            "Invalid or expired token",
        )

    user = db.get(
        User,
        uid,
    )

    if not user:

        raise HTTPException(
            401,
            "User not found",
        )

    return user


def require_deposit_address():

    if not USDT_TRON_ADDRESS:

        raise HTTPException(
            503,
            "USDT TRC20 receiving address is not configured",
        )

    return USDT_TRON_ADDRESS


# ============================================================
# HEALTH
# ============================================================

@app.get("/health")
def health():

    return {
        "status": "ok",
        "app": APP_NAME,
        "network": "TRC20 (TRON)",
        "package_usdt": PACKAGE_USDT,
        "package_asc": PACKAGE_ASC,
        "max_supply": MAX_SUPPLY,
        "usdt_address_configured": bool(
            USDT_TRON_ADDRESS
        ),
    }


# ============================================================
# PHONE OTP
# ============================================================

@app.post("/auth/request-otp")
def request_otp(
    data: PhoneRequest,
    db: Session = Depends(db_dep),
):

    phone = normalize_phone(
        data.phone
    )

    code = f"{secrets.randbelow(1_000_000):06d}"

    otp = Otp(
        phone=phone,
        code_hash=make_otp_hash(code),
        expires_at=now() + timedelta(minutes=5),
    )

    db.add(otp)
    db.commit()

    if TELEGRAM_GATEWAY_TOKEN:

        try:

            with httpx.Client(
                timeout=15
            ) as client:

                response = client.post(
                    "https://gatewayapi.telegram.org/sendVerificationMessage",
                    headers={
                        "Authorization":
                        f"Bearer {TELEGRAM_GATEWAY_TOKEN}"
                    },
                    json={
                        "phone_number": phone,
                        "code": code,
                        "code_length": 6,
                        "ttl": 300,
                    },
                )

                if response.status_code >= 400:

                    raise HTTPException(
                        502,
                        "Telegram OTP provider rejected the request",
                    )

        except httpx.HTTPError:

            raise HTTPException(
                502,
                "Telegram OTP provider is unavailable",
            )

        return {
            "sent": True,
            "channel": "telegram_gateway",
        }

    return {
        "sent": False,
        "channel": "not_configured",
        "message": "OTP provider is not configured",
    }


@app.post("/auth/verify-otp")
def verify_otp(
    data: OtpVerify,
    db: Session = Depends(db_dep),
):

    phone = normalize_phone(
        data.phone
    )

    otp = (
        db.query(Otp)
        .filter(
            Otp.phone == phone,
            Otp.used == False,
        )
        .order_by(
            Otp.id.desc()
        )
        .first()
    )

    if (
        not otp
        or otp.expires_at < now()
    ):

        raise HTTPException(
            400,
            "OTP expired or not found",
        )

    if otp.attempts >= 5:

        raise HTTPException(
            429,
            "Too many OTP attempts",
        )

    otp.attempts += 1

    if not verify_otp_hash(
        data.code,
        otp.code_hash,
    ):

        db.commit()

        raise HTTPException(
            400,
            "Invalid OTP",
        )

    otp.used = True

    user = (
        db.query(User)
        .filter(
            User.phone == phone
        )
        .first()
    )

    if not user:

        user = User(
            phone=phone
        )

        db.add(user)
        db.commit()
        db.refresh(user)

    db.commit()

    return {
        "token": token_for(user),
        "user": serialize_user(user),
    }


# ============================================================
# GOOGLE LOGIN
# ============================================================

@app.post("/auth/google")
def google_login(
    data: GoogleRequest,
    db: Session = Depends(db_dep),
):

    if not GOOGLE_CLIENT_ID:

        raise HTTPException(
            503,
            "Google authentication is not configured",
        )

    try:

        from google.oauth2 import id_token
        from google.auth.transport import requests

        info = id_token.verify_oauth2_token(
            data.id_token,
            requests.Request(),
            GOOGLE_CLIENT_ID,
        )

    except Exception:

        raise HTTPException(
            401,
            "Invalid Google ID token",
        )

    sub = info.get(
        "sub"
    )

    if not sub:

        raise HTTPException(
            401,
            "Google account ID missing",
        )

    user = (
        db.query(User)
        .filter(
            User.google_sub == sub
        )
        .first()
    )

    if not user:

        user = User(
            google_sub=sub
        )

        db.add(user)
        db.commit()
        db.refresh(user)

    return {
        "token": token_for(user),
        "user": serialize_user(user),
    }


# ============================================================
# TELEGRAM
# ============================================================

@app.post("/auth/telegram")
def telegram_login(
    data: TelegramRequest,
    db: Session = Depends(db_dep),
):

    normalize_phone(
        data.phone
    )

    raise HTTPException(
        501,
        "Use Telegram Gateway OTP verification",
    )


# ============================================================
# USER
# ============================================================

@app.get("/me")
def me(
    user: User = Depends(current_user),
):

    return serialize_user(
        user
    )


# ============================================================
# PURCHASE
# ============================================================

@app.post("/purchases/create")
def create_purchase(
    user: User = Depends(current_user),
    db: Session = Depends(db_dep),
):

    address = require_deposit_address()

    purchase = Purchase(
        user_id=user.id,
        amount_usdt=PACKAGE_USDT,
        amount_asc=PACKAGE_ASC,
        deposit_address=address,
    )

    db.add(purchase)
    db.commit()
    db.refresh(purchase)

    return {
        "id": purchase.id,
        "amount_usdt": purchase.amount_usdt,
        "amount_asc": purchase.amount_asc,
        "network": "TRC20",
        "address": address,
        "status": purchase.status,
    }


@app.get("/purchases/{purchase_id}")
def purchase_status(
    purchase_id: int,
    user: User = Depends(current_user),
    db: Session = Depends(db_dep),
):

    purchase = db.get(
        Purchase,
        purchase_id,
    )

    if (
        not purchase
        or purchase.user_id != user.id
    ):

        raise HTTPException(
            404,
            "Purchase not found",
        )

    verify_purchase_on_chain(
        purchase,
        db,
    )

    return {
        "id": purchase.id,
        "amount_usdt": purchase.amount_usdt,
        "amount_asc": purchase.amount_asc,
        "status": purchase.status,
        "txid": purchase.txid,
    }


# ============================================================
# KYC
# ============================================================

@app.post("/kyc/payment")
def create_kyc_payment(
    user: User = Depends(current_user),
    db: Session = Depends(db_dep),
):

    address = require_deposit_address()

    if user.kyc_status == "verified":

        raise HTTPException(
            400,
            "KYC is already verified",
        )

    payment = KycPayment(
        user_id=user.id,
        amount_usdt=KYC_FEE_USDT,
        deposit_address=address,
    )

    db.add(payment)
    db.commit()
    db.refresh(payment)

    return {
        "id": payment.id,
        "amount_usdt": KYC_FEE_USDT,
        "network": "TRC20",
        "address": address,
        "status": payment.status,
    }


@app.get("/kyc/status")
def kyc_status(
    user: User = Depends(current_user),
    db: Session = Depends(db_dep),
):

    payment = (
        db.query(KycPayment)
        .filter(
            KycPayment.user_id == user.id
        )
        .order_by(
            KycPayment.id.desc()
        )
        .first()
    )

    if payment:

        verify_kyc_on_chain(
            payment,
            db,
        )

    db.refresh(user)

    return {
        "status": user.kyc_status,
        "payment_status":
            payment.status
            if payment
            else None,
    }


# ============================================================
# TRANSACTION HISTORY
# ============================================================

@app.get("/transactions")
def transactions(
    user: User = Depends(current_user),
    db: Session = Depends(db_dep),
):

    rows = (
        db.query(Ledger)
        .filter(
            Ledger.user_id == user.id
        )
        .order_by(
            Ledger.id.desc()
        )
        .limit(100)
        .all()
    )

    return [
        {
            "kind": row.kind,
            "amount": row.amount,
            "reference": row.reference,
            "note": row.note,
            "created_at":
                row.created_at.isoformat(),
        }
        for row in rows
    ]


# ============================================================
# ASC SEND
# ============================================================

@app.post("/wallet/send")
def wallet_send(
    data: SendRequest,
    user: User = Depends(current_user),
    db: Session = Depends(db_dep),
):

    if user.balance < data.amount:

        raise HTTPException(
            400,
            "Insufficient ASC balance",
        )

    raise HTTPException(
        503,
        "ASC blockchain transfer is not configured. No balance was deducted.",
    )


# ============================================================
# TRON
# ============================================================

def tron_trc20_transfers(
    address: str
):

    url = (
        "https://api.trongrid.io/v1/accounts/"
        f"{address}/transactions/trc20"
    )

    params = {
        "only_confirmed": "true",
        "limit": 200,
        "contract_address":
            TRON_USDT_CONTRACT,
    }

    headers = {}

    if TRON_API_KEY:

        headers[
            "TRON-PRO-API-KEY"
        ] = TRON_API_KEY

    try:

        with httpx.Client(
            timeout=20
        ) as client:

            response = client.get(
                url,
                params=params,
                headers=headers,
            )

            response.raise_for_status()

            return response.json().get(
                "data",
                [],
            )

    except httpx.HTTPError:

        return []


def transfer_amount_usdt(
    tx: dict
) -> float:

    value = float(
        tx.get(
            "value",
            0,
        )
    )

    decimals = int(
        tx.get(
            "token_info",
            {}
        ).get(
            "decimals",
            6,
        )
    )

    return value / (
        10 ** decimals
    )


# ============================================================
# PURCHASE VERIFICATION
# ============================================================

def verify_purchase_on_chain(
    purchase: Purchase,
    db: Session,
):

    if purchase.status == "confirmed":
        return

    if not USDT_TRON_ADDRESS:
        return

    transfers = tron_trc20_transfers(
        USDT_TRON_ADDRESS
    )

    for tx in transfers:

        txid = tx.get(
            "transaction_id"
        )

        to_addr = tx.get(
            "to"
        )

        amount = transfer_amount_usdt(
            tx
        )

        if not txid:
            continue

        if to_addr != USDT_TRON_ADDRESS:
            continue

        if amount < purchase.amount_usdt:
            continue

        existing = (
            db.query(Purchase)
            .filter(
                Purchase.txid == txid
            )
            .first()
        )

        if existing:
            continue

        purchase.status = "confirmed"

        purchase.txid = txid

        purchase.confirmed_at = now()

        reference = (
            f"purchase:{purchase.id}"
        )

        already_credited = (
            db.query(Ledger)
            .filter(
                Ledger.reference == reference
            )
            .first()
        )

        if not already_credited:

            user = db.get(
                User,
                purchase.user_id,
            )

            user.balance += (
                purchase.amount_asc
            )

            db.add(
                Ledger(
                    user_id=user.id,
                    kind="purchase_credit",
                    amount=purchase.amount_asc,
                    reference=reference,
                    note=(
                        "Confirmed USDT payment "
                        f"{txid}"
                    ),
                )
            )

        db.commit()

        return


# ============================================================
# KYC VERIFICATION
# ============================================================

def verify_kyc_on_chain(
    payment: KycPayment,
    db: Session,
):

    if payment.status == "confirmed":
        return

    if not USDT_TRON_ADDRESS:
        return

    transfers = tron_trc20_transfers(
        USDT_TRON_ADDRESS
    )

    for tx in transfers:

        txid = tx.get(
            "transaction_id"
        )

        to_addr = tx.get(
            "to"
        )

        amount = transfer_amount_usdt(
            tx
        )

        if not txid:
            continue

        if to_addr != USDT_TRON_ADDRESS:
            continue

        if amount < payment.amount_usdt:
            continue

        existing = (
            db.query(KycPayment)
            .filter(
                KycPayment.txid == txid
            )
            .first()
        )

        if existing:
            continue

        payment.status = "confirmed"

        payment.txid = txid

        payment.confirmed_at = now()

        user = db.get(
            User,
            payment.user_id,
        )

        user.kyc_status = "verified"

        db.commit()

        return
