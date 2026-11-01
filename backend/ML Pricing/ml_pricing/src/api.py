from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from .predict import PricePredictor

app = FastAPI(title="REBYTE Phone Price Prediction", version="1.0.0")
predictor = None


class PriceRequest(BaseModel):
    deviceAge: float
    brand: str
    model: str
    ramCapacity: float
    storage: float
    internalPerfromanceOverallMark: float
    screenDmgScore: float
    totalDmgScore: float
    hasScreenDamage: int
    msrp: float = Field(gt=0)


@app.on_event("startup")
def load_model():
    global predictor
    predictor = PricePredictor("without_model")


@app.post("/predict-price")
def predict_price(request: PriceRequest):
    try:
        return predictor.predict(request.model_dump())
    except (ValueError, FileNotFoundError) as e:
        raise HTTPException(status_code=422, detail=str(e))
