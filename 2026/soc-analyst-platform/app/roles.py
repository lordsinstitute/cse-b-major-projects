import enum


class Role(str, enum.Enum):
    """
    Fixed set of roles for the platform.

    Add new roles here (and only here) as the platform grows —
    every route's role check should reference this enum, never raw strings,
    so a typo like "Admin" vs "admin" can't silently create an access-control bug.
    """
    ANALYST = "analyst"
    ADMIN = "admin"