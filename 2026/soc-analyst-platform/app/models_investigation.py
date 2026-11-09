"""
The Investigation model — Razzaq's LLM agent's output for a given alert:
the incident brief, the reconstructed timeline, and the citations linking
every claim back to real log data.
"""

import enum

from sqlalchemy import Column, Integer, String, Text, DateTime, JSON, ForeignKey, Enum, func
from sqlalchemy.orm import relationship

from app.database import Base


class InvestigationStatus(str, enum.Enum):
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    FAILED = "failed"


class Investigation(Base):
    __tablename__ = "investigations"

    id = Column(Integer, primary_key=True, index=True)

    alert_id = Column(Integer, ForeignKey("alerts.id"), unique=True, nullable=False)
    alert = relationship("Alert")

    status = Column(Enum(InvestigationStatus), default=InvestigationStatus.IN_PROGRESS, nullable=False)

    incident_brief = Column(Text, nullable=True)
    timeline = Column(JSON, default=list, nullable=False)
    citations = Column(JSON, default=list, nullable=False)
    confidence_score = Column(String, nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    completed_at = Column(DateTime(timezone=True), nullable=True)