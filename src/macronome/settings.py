import os
from dotenv import load_dotenv

load_dotenv()

SUPABASE_PASSWORD = os.getenv("SUPABASE_PASSWORD")