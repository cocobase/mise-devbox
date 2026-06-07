import os
import redis
from qdrant_client import QdrantClient
from dotenv import load_dotenv

load_dotenv()

def test_connections():
    print("--- AI-Agent Harness Smoke Test ---")
    
    # 1. Test Redis Connection
    redis_url = os.getenv("REDIS_URL", "redis://localhost:6379/0")
    try:
        r = redis.from_url(redis_url)
        r.set("harness_test", "success")
        value = r.get("harness_test")
        print(f"✅ Redis connection: {value.decode('utf-8')}")
    except Exception as e:
        print(f"❌ Redis connection failed: {e}")

    # 2. Test Qdrant Connection
    qdrant_host = os.getenv("QDRANT_HOST", "localhost")
    qdrant_port = int(os.getenv("QDRANT_PORT", 6333))
    try:
        client = QdrantClient(host=qdrant_host, port=qdrant_port)
        collections = client.get_collections()
        print(f"✅ Qdrant connection: Found {len(collections.collections)} collections")
    except Exception as e:
        print(f"❌ Qdrant connection failed: {e}")

if __name__ == "__main__":
    test_connections()
