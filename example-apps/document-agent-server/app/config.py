import os

from dotenv import load_dotenv

load_dotenv()

GOOGLE_API_KEY = os.environ["GOOGLE_API_KEY"]
GEMINI_MODEL = os.environ.get("GEMINI_MODEL", "gemini-2.5-flash-lite")
MAX_CONCURRENT = int(os.environ.get("MAX_CONCURRENT", "5"))

PRICE_INPUT_PER_M = 0.075
PRICE_OUTPUT_PER_M = 0.30
