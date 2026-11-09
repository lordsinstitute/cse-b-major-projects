from fastapi import FastAPI

app = FastAPI()

@app.get("/")
def read_root():
    return {"message": "SOC Analyst Platform backend is running"}