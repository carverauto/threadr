# modules/messages/models.py

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
    embedding: Optional[list] = Field(None, description="Message embedding (e.g. BERT, GPT-3, etc.)")


# Vector Embedding Messages class
class VectorEmbeddingMessage(BaseModel):
    message_id: int = Field(None, description="Message ID")
    content: str = Field(..., description="Message content")
