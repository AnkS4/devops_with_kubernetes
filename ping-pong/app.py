# import os
# import json
from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.responses import JSONResponse
# from pathlib import Path
from sqlalchemy import create_engine, Column, Integer, String
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session
import os

app = FastAPI()

# Database setup
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://admin:admin123@postgres:5432/pingpong")
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

# Database models
class PongCount(Base):
    __tablename__ = "pong_counts"
    
    id = Column(Integer, primary_key=True, index=True)
    count = Column(Integer, default=0)

# Create tables
Base.metadata.create_all(bind=engine)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def init_db():
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        if db.query(PongCount).count() == 0:
            db.add(PongCount(count=0))
            db.commit()
    finally:
        db.close()

def get_or_create_counter(db: Session) -> PongCount:
    counter = db.query(PongCount).first()
    if not counter:
        counter = PongCount(count=0)
        db.add(counter)
        db.commit()
        db.refresh(counter)
    return counter

def increment_counter(db: Session) -> int:
    counter = get_or_create_counter(db)
    counter.count += 1
    db.commit()
    db.refresh(counter)
    return counter.count

# Old implementation (commented out)
# pong_count = 0
# SHARED_FILE = os.getenv('SHARED_VOLUME_PATH', '/app/shared/request_count.txt')
# Path(SHARED_FILE).parent.mkdir(parents=True, exist_ok=True)
# def read_count():
#     try:
#         with open(SHARED_FILE, 'r') as f:
#             return int(f.read().strip() or 0)
#     except (FileNotFoundError, ValueError):
#         return 0
# def write_count(count):
#     with open(SHARED_FILE, 'w') as f:
#         f.write(str(count))

@app.get("/")
def root():
    return {"message": "Ping Pong API with Database"}

@app.get("/pingpong")
def pingpong(db: Session = Depends(get_db)):
    try:
        count = increment_counter(db)
        return {"message": f"pong {count}"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

@app.get("/pongs")
def get_pongs(db: Session = Depends(get_db)):
    try:
        counter = db.query(PongCount).first()
        if not counter:
            return {"pongs": 0}
        return {"pongs": counter.count}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

@app.get("/health")
async def health_check():
    """Health check endpoint - just returns OK if server is running"""
    return {"status": "healthy"}

@app.get("/db-health")
async def db_health_check():
    """Database health check"""
    try:
        db = SessionLocal()
        db.execute(text("SELECT 1"))
        db.close()
        return {"status": "healthy", "database": "connected"}
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Database unavailable: {str(e)}")
