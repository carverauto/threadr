# src/models.py

from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


class NATSMessage(BaseModel):
    id: Optional[int] = Field(None, description="Message ID")
    message: str = Field(..., description="Message content")
    nick: str = Field(..., description="Nickname of the message sender")
    channel: Optional[str] = Field(None, description="Channel where the message was sent")
    timestamp: datetime = Field(..., description="Timestamp of the message")
    platform: Optional[str] = Field(None, description="Platform from which the message was sent")