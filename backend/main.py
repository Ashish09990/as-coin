import os
import secrets
import hashlib
import sqlite3
from datetime import datetime, timezone, timedelta

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

# ============================================================
# AS COIN SERVER
# ============================================================

APP_NAME = "AS COIN"
SYMBOL = "ASC"

DAILY_REWARD = 0.14
KYC_FEE_USDT = 1.0
MIGRATION_DAYS = 365
MINING_END_YEAR = 2130
MAX_SUPPLY = 20_000_000

DATABASE = os.getenv("ASC_DATABASE", "ascoin.db")
ADMIN_SECRET = os.getenv("ASC_ADMIN_SECRET", "")

app = FastAPI(
    title="AS COIN API",
    version="1.0.0",
)


# ============================================================
# DATABASE
# ============================================================

def db():
    conn = sqlite3.connect(DATABASE)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    conn = db()

    conn.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            phone TEXT UNIQUE NOT NULL,
            account_id TEXT UNIQUE NOT NULL,
            wallet_address TEXT UNIQUE NOT NULL,
            balance REAL NOT NULL DEFAULT 0,
            kyc_verified INTEGER NOT NULL DEFAULT 0,
            kyc_paid INTEGER NOT NULL DEFAULT 0,
            mining_started TEXT,
            last_claim TEXT,
            created_at TEXT NOT NULL
        )
    """)

    conn.execute("""
        CREATE TABLE IF NOT EXISTS otp_codes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            phone TEXT NOT NULL,
            code_hash TEXT NOT NULL,
            expires_at TEXT NOT NULL,
            used INTEGER NOT NULL DEFAULT 0
        )
    """)

    conn.execute("""
        CREATE TABLE IF NOT EXISTS transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            tx_id TEXT UNIQUE NOT NULL,
            sender TEXT,
            recipient TEXT,
            amount REAL NOT NULL,
            tx_type TEXT NOT NULL,
            status TEXT NOT NULL,
            created_at TEXT NOT NULL
        )
    """)

    conn.commit()
    conn.close()


init_db()


# ============================================================
# HELPERS
# ============================================================

def now():
    return datetime.now(timezone.utc)


def iso(dt):
    return dt.astimezone(timezone.utc).isoformat()


def hash_value(value):
    return hashlib.sha256(value.encode()).hexdigest()


def make_account_id(phone):
    digest = hashlib.sha256(
        ("ASCOIN:" + phone).encode()
    ).hexdigest()[:16].upper()

    return "ASC-" + digest


def make_wallet_address(account_id):
    digest = hashlib.sha256(
        ("WALLET:" + account_id).encode()
    ).hexdigest().upper()

    return "ASC-" + digest[:32]


def get_user(phone):
    conn = db()
    user = conn.execute(
        "SELECT * FROM users WHERE phone = ?",
        (phone,),
    ).fetchone()
    conn.close()
    return user


# ============================================================
# REQUEST MODELS
# ============================================================

class OTPRequest(BaseModel):
    phone: str = Field(min_length=6, max_length=30)


class OTPVerify(BaseModel):
    phone: str = Field(min_length=6, max_length=30)
    code: str = Field(min_length=4, max_length=10)


class ClaimRequest(BaseModel):
    phone: str


class TransferRequest(BaseModel):
    sender_phone: str
    recipient_address: str
    amount: float = Field(gt=0)


class KYCRequest(BaseModel):
    phone: str
    payment_txid: str = Field(min_length=5)


# ============================================================
# HEALTH
# ============================================================

@app.get("/")
def root():
    return {
        "app": APP_NAME,
        "symbol": SYMBOL,
        "status": "online",
        "mode": "server",
    }


@app.get("/protocol")
def protocol():
    return {
        "maximum_supply": MAX_SUPPLY,
        "daily_reward": DAILY_REWARD,
        "kyc_fee_usdt": KYC_FEE_USDT,
        "migration_days": MIGRATION_DAYS,
        "mining_end_year": MINING_END_YEAR,
    }


# ============================================================
# OTP
# ============================================================

@app.post("/auth/request-otp")
def request_otp(data: OTPRequest):
    phone = data.phone.strip()

    # Real provider integration required.
    # No OTP is returned by this API.
    otp = f"{secrets.randbelow(1_000_000):06d}"

    conn = db()

    conn.execute(
        "UPDATE otp_codes SET used = 1 WHERE phone = ?",
        (phone,),
    )

    conn.execute(
        """
        INSERT INTO otp_codes
        (phone, code_hash, expires_at)
        VALUES (?, ?, ?)
        """,
        (
            phone,
            hash_value(otp),
            iso(now() + timedelta(minutes=5)),
        ),
    )

    conn.commit()
    conn.close()

    # IMPORTANT:
    # Connect Telegram Gateway/SMS provider here.
    # Never return the OTP to the mobile app.

    return {
        "success": True,
        "message": "Verification code sent.",
    }


@app.post("/auth/verify-otp")
def verify_otp(data: OTPVerify):
    phone = data.phone.strip()

    conn = db()

    row = conn.execute(
        """
        SELECT *
        FROM otp_codes
        WHERE phone = ?
          AND used = 0
        ORDER BY id DESC
        LIMIT 1
        """,
        (phone,),
    ).fetchone()

    if not row:
        conn.close()
        raise HTTPException(
            status_code=400,
            detail="OTP not found or already used.",
        )

    if datetime.fromisoformat(
        row["expires_at"]
    ) < now():
        conn.close()
        raise HTTPException(
            status_code=400,
            detail="OTP expired.",
        )

    if not secrets.compare_digest(
        row["code_hash"],
        hash_value(data.code),
    ):
        conn.close()
        raise HTTPException(
            status_code=401,
            detail="Invalid OTP.",
        )

    conn.execute(
        "UPDATE otp_codes SET used = 1 WHERE id = ?",
        (row["id"],),
    )

    user = conn.execute(
        "SELECT * FROM users WHERE phone = ?",
        (phone,),
    ).fetchone()

    if not user:
        account_id = make_account_id(phone)
        wallet = make_wallet_address(account_id)

        conn.execute(
            """
            INSERT INTO users
            (
                phone,
                account_id,
                wallet_address,
                created_at
            )
            VALUES (?, ?, ?, ?)
            """,
            (
                phone,
                account_id,
                wallet,
                iso(now()),
            ),
        )

    conn.commit()

    user = conn.execute(
        "SELECT * FROM users WHERE phone = ?",
        (phone,),
    ).fetchone()

    conn.close()

    return {
        "success": True,
        "account_id": user["account_id"],
        "wallet_address": user["wallet_address"],
    }


# ============================================================
# ACCOUNT
# ============================================================

@app.get("/account/{phone}")
def account(phone: str):
    user = get_user(phone)

    if not user:
        raise HTTPException(
            status_code=404,
            detail="Account not found.",
        )

    return {
        "account_id": user["account_id"],
        "wallet_address": user["wallet_address"],
        "balance": user["balance"],
        "kyc_verified": bool(user["kyc_verified"]),
        "mining_started": user["mining_started"],
        "last_claim": user["last_claim"],
    }


# ============================================================
# MINING START
# ============================================================

@app.post("/mining/start")
def start_mining(data: ClaimRequest):
    user = get_user(data.phone)

    if not user:
        raise HTTPException(
            status_code=404,
            detail="Account not found.",
        )

    if not user["kyc_verified"]:
        raise HTTPException(
            status_code=403,
            detail="KYC verification required.",
        )

    if user["mining_started"]:
        return {
            "success": True,
            "message": "Mining already started.",
            "mining_started": user["mining_started"],
        }

    started = iso(now())

    conn = db()
    conn.execute(
        """
        UPDATE users
        SET mining_started = ?
        WHERE phone = ?
        """,
        (started, data.phone),
    )
    conn.commit()
    conn.close()

    return {
        "success": True,
        "mining_started": started,
    }


# ============================================================
# DAILY CLAIM
# ============================================================

@app.post("/mining/claim")
def claim(data: ClaimRequest):
    conn = db()

    user = conn.execute(
        "SELECT * FROM users WHERE phone = ?",
        (data.phone,),
    ).fetchone()

    if not user:
        conn.close()
        raise HTTPException(
            status_code=404,
            detail="Account not found.",
        )

    if not user["kyc_verified"]:
        conn.close()
        raise HTTPException(
            status_code=403,
            detail="KYC verification required.",
        )

    if not user["mining_started"]:
        conn.close()
        raise HTTPException(
            status_code=403,
            detail="Mining has not started.",
        )

    current = now()

    if user["last_claim"]:
        previous = datetime.fromisoformat(
            user["last_claim"]
        )

        elapsed = current - previous

        if elapsed < timedelta(hours=24):
            remaining = timedelta(hours=24) - elapsed

            conn.close()

            raise HTTPException(
                status_code=429,
                detail={
                    "message": "Daily reward already claimed.",
                    "remaining_seconds":
                        int(remaining.total_seconds()),
                },
            )

    # Supply protection
    total = conn.execute(
        """
        SELECT COALESCE(SUM(amount), 0)
        FROM transactions
        WHERE tx_type = 'MINING'
          AND status = 'CONFIRMED'
        """
    ).fetchone()[0]

    if total + DAILY_REWARD > MAX_SUPPLY:
        conn.close()
        raise HTTPException(
            status_code=409,
            detail="Maximum AS COIN supply reached.",
        )

    new_balance = user["balance"] + DAILY_REWARD

    tx_id = "MIN-" + secrets.token_hex(16).upper()
    timestamp = iso(current)

    conn.execute(
        """
        UPDATE users
        SET balance = ?,
            last_claim = ?
        WHERE phone = ?
        """,
        (
            new_balance,
            timestamp,
            data.phone,
        ),
    )

    conn.execute(
        """
        INSERT INTO transactions
        (
            tx_id,
            sender,
            recipient,
            amount,
            tx_type,
            status,
            created_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        (
            tx_id,
            None,
            user["wallet_address"],
            DAILY_REWARD,
            "MINING",
            "CONFIRMED",
            timestamp,
        ),
    )

    conn.commit()
    conn.close()

    return {
        "success": True,
        "amount": DAILY_REWARD,
        "balance": new_balance,
        "tx_id": tx_id,
        "next_claim_after": iso(
            current + timedelta(hours=24)
        ),
    }


# ============================================================
# KYC PAYMENT
# ============================================================

@app.post("/kyc/request")
def request_kyc(data: KYCRequest):
    user = get_user(data.phone)

    if not user:
        raise HTTPException(
            status_code=404,
            detail="Account not found.",
        )

    if user["kyc_verified"]:
        return {
            "success": True,
            "message": "KYC already verified.",
        }

    # IMPORTANT:
    # Payment TXID must be checked against the
    # configured USDT TRC20 receiver and USDT contract.
    #
    # Do NOT trust the TXID sent by the mobile app alone.
    # Blockchain verification worker/backend must confirm it.

    raise HTTPException(
        status_code=501,
        detail=(
            "Blockchain payment verification is not "
            "configured yet. KYC cannot be marked successful."
        ),
    )


# ============================================================
# SEND ASC
# ============================================================

@app.post("/wallet/send")
def send(data: TransferRequest):
    conn = db()

    sender = conn.execute(
        "SELECT * FROM users WHERE phone = ?",
        (data.sender_phone,),
    ).fetchone()

    if not sender:
        conn.close()
        raise HTTPException(
            status_code=404,
            detail="Sender account not found.",
        )

    if not sender["kyc_verified"]:
        conn.close()
        raise HTTPException(
            status_code=403,
            detail="KYC verification required.",
        )

    if data.recipient_address == sender["wallet_address"]:
        conn.close()
        raise HTTPException(
            status_code=400,
            detail="Cannot send to your own address.",
        )

    if data.amount > sender["balance"]:
        conn.close()
        raise HTTPException(
            status_code=400,
            detail="Insufficient ASC balance.",
        )

    recipient = conn.execute(
        """
        SELECT *
        FROM users
        WHERE wallet_address = ?
        """,
        (data.recipient_address,),
    ).fetchone()

    if not recipient:
        conn.close()
        raise HTTPException(
            status_code=404,
            detail="Recipient ASC wallet not found.",
        )

    if not recipient["kyc_verified"]:
        conn.close()
        raise HTTPException(
            status_code=403,
            detail="Recipient is not KYC verified.",
        )

    tx_id = "TX-" + secrets.token_hex(16).upper()
    timestamp = iso(now())

    sender_balance = sender["balance"] - data.amount
    recipient_balance = (
        recipient["balance"] + data.amount
    )

    conn.execute(
        """
        UPDATE users
        SET balance = ?
        WHERE phone = ?
        """,
        (
            sender_balance,
            data.sender_phone,
        ),
    )

    conn.execute(
        """
        UPDATE users
        SET balance = ?
        WHERE wallet_address = ?
        """,
        (
            recipient_balance,
            data.recipient_address,
        ),
    )

    conn.execute(
        """
        INSERT INTO transactions
        (
            tx_id,
            sender,
            recipient,
            amount,
            tx_type,
            status,
            created_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        (
            tx_id,
            sender["wallet_address"],
            recipient["wallet_address"],
            data.amount,
            "TRANSFER",
            "CONFIRMED",
            timestamp,
        ),
    )

    conn.commit()
    conn.close()

    return {
        "success": True,
        "tx_id": tx_id,
        "amount": data.amount,
        "balance": sender_balance,
        "status": "CONFIRMED",
    }


# ============================================================
# TRANSACTION HISTORY
# ============================================================

@app.get("/transactions/{phone}")
def transactions(phone: str):
    user = get_user(phone)

    if not user:
        raise HTTPException(
            status_code=404,
            detail="Account not found.",
        )

    conn = db()

    rows = conn.execute(
        """
        SELECT *
        FROM transactions
        WHERE sender = ?
           OR recipient = ?
        ORDER BY id DESC
        """,
        (
            user["wallet_address"],
            user["wallet_address"],
        ),
    ).fetchall()

    conn.close()

    return {
        "transactions": [
            dict(row)
            for row in rows
        ]
  }
