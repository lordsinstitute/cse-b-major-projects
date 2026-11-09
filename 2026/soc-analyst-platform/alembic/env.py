from logging.config import fileConfig

from sqlalchemy import engine_from_config
from sqlalchemy import pool

from alembic import context

# --- Wired in for this project ---
from app.config import settings
from app.database import Base
from app import models, models_integration, models_alert, models_investigation, models_audit  # noqa: F401
from app.encrypted_type import EncryptedString


def render_item(type_, obj, autogen_context):
    """
    Without this, autogenerate writes `app.encrypted_type.EncryptedString()`
    into migration files but never adds the import for it — every migration
    touching an encrypted column would fail with NameError: name 'app' is
    not defined. This tells Alembic to add the import explicitly and use
    the short class name instead.
    """
    if type_ == "type" and isinstance(obj, EncryptedString):
        autogen_context.imports.add("from app.encrypted_type import EncryptedString")
        return "EncryptedString()"
    return False


config = context.config

config.set_main_option("sqlalchemy.url", settings.database_url)

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        render_item=render_item,
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection, target_metadata=target_metadata, render_item=render_item
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()