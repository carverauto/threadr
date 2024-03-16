from openai import OpenAI
import os

client = OpenAI(api_key=os.getenv("OPEN_AI_KEY"))

try:
    #response = client.embedding.create(
    response = client.embeddings.create(
        model="text-embedding-3-small",
        input="The quick brown fox jumps over the lazy dog"
    )
    print(response)
except Exception as e:
    print(f"API call failed: {e}")

