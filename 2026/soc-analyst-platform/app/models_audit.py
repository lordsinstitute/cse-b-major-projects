"""
Persistent audit trail — the database version of what your RBAC denials
currently only print to a console logger.
"""

from sqlalchemy import Column, Integer, String, DateTime, JSON, ForeignKey, func

from app.database import Base


class AuditLog(Base):
    __tablename__ = "audit_logs"

    id = Column(Integer, primary_key=True, index=True)

    event_type = Column(String, index=True, nullable=False)
    actor_type = Column(String, nullable=False)
    actor_user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    alert_id = Column(Integer, ForeignKey("alerts.id"), nullable=True)
    detail = Column(JSON, default=dict, nullable=False)

    created_at = Column(DateTime(timezone=True), server_default=func.now(), index=True)