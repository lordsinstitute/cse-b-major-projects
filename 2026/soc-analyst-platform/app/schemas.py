from pydantic import BaseModel, EmailStr

from app.roles import Role


class UserCreate(BaseModel):
    email: EmailStr
    password: str
    # Deliberately no "role" field here — self-registration always creates
    # an analyst. Nobody should be able to grant themselves admin by just
    # signing up. Only an existing admin can promote someone (see RoleUpdate).


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class UserOut(BaseModel):
    id: int
    email: EmailStr
    role: Role

    class Config:
        from_attributes = True


class RoleUpdate(BaseModel):
    role: Role


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class RefreshRequest(BaseModel):
    refresh_token: str


class AccessTokenOnly(BaseModel):
    access_token: str
    token_type: str = "bearer"