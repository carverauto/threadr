# modules/messages/models.py

from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


class Mention(BaseModel):
    id: int = Field(..., description="Mention ID")
    email: Optional[str] = Field(None, description="Email address of the mentioned user")
    username: Optional[str] = Field(None, description="Username of the mentioned user")
    avatar: Optional[str] = Field(None, description="Avatar URL of the mentioned user")
    global_name: Optional[str] = Field(None, description="Global name of the mentioned user")
    verified: Optional[bool] = Field(None, description="Verification status of the mentioned user")
    mfa_enabled: Optional[bool] = Field(None, description="MFA status of the mentioned user")
    bot: Optional[bool] = Field(None, description="Bot status of the mentioned user")


class User(BaseModel):
    id: Optional[str] = Field(None, description="User ID")
    email: Optional[str] = Field(None, description="Email address of the user")
    username: Optional[str] = Field(None, description="Username of the user")
    avatar: Optional[str] = Field(None, description="Avatar URL of the user")
    global_name: Optional[str] = Field(None, description="Global name of the user")
    verified: Optional[bool] = Field(None, description="Verification status of the user")
    mfa_enabled: Optional[bool] = Field(None, description="MFA status of the user")
    bot: Optional[bool] = Field(None, description="Bot status of the user")


class NATSMessage(BaseModel):
    id: Optional[int] = Field(None, description="Message ID")
    message: str = Field(..., description="Message content")
    user: Optional[User] = Field(None, description="User who sent the message")
    mentions: Optional[list[Mention]] = Field(None, description="List of mentioned users")
    channel: Optional[str] = Field(None, description="Channel where the message was sent")
    channel_id: Optional[int] = Field(None, description="Channel ID where the message was sent")
    timestamp: datetime = Field(..., description="Timestamp of the message")
    platform: Optional[str] = Field(None, description="Platform from which the message was sent")
    server: Optional[str] = Field(None, description="IRC or Discord server where the message was sent")
    embedding: Optional[list] = Field(None, description="Message embedding (e.g. BERT, GPT-3, etc.)")


# Vector Embedding Messages class
class Content(BaseModel):
    response: str
    channel: str
    timestamp: str


class VectorEmbeddingMessage(BaseModel):
    message_id: int
    content: Content
