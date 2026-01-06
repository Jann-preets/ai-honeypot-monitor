from fastapi import FastAPI, Request, Form
from fastapi.middleware.cors import CORSMiddleware
import datetime
from collections import defaultdict
import requests
from motor.motor_asyncio import AsyncIOMotorClient

app = FastAPI()

# --- 1. MongoDB Configuration ---
# Replace this with your real connection string from MongoDB Atlas
MONGO_DETAILS = "mongodb+srv://janarpreethika:janar@cluster0.erkmugt.mongodb.net/?appName=Cluster0"
client = AsyncIOMotorClient(MONGO_DETAILS)
database = client.honeypot
logs_collection = database.get_collection("attack_logs")
blacklist_collection = database.get_collection("blacklist")

# --- 2. Local Configuration ---
THRESHOLD = 5
WINDOW_SECONDS = 30
attack_history = defaultdict(list)
blocked_ips = set()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Load existing blacklist from MongoDB on startup
@app.on_event("startup")
async def load_blacklist():
    async for entry in blacklist_collection.find():
        blocked_ips.add(entry["ip"])
    print(f"✅ Loaded {len(blocked_ips)} blocked IPs from Cloud.")

# --- 3. Routes ---

@app.post("/block/{ip}")
async def block_ip(ip: str):
    if ip not in blocked_ips:
        blocked_ips.add(ip)
        # Save to MongoDB Atlas permanently
        await blacklist_collection.insert_one({
            "ip": ip, 
            "blocked_at": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        })
        print(f"🚫 PERMANENT BLOCK: {ip} saved to MongoDB.")
    return {"status": "success", "blocked_ip": ip}

@app.post("/capture")
async def capture_attack(
    request: Request,
    username: str = Form(...),
    password: str = Form(...),
    fax_number: str = Form(None)
):
    # 1. IP Identification
    client_ip = request.client.host
    if client_ip == "127.0.0.1":
        try:
            client_ip = requests.get('https://api.ipify.org').text
        except:
            client_ip = "127.0.0.1"

    # 🛑 2. Blacklist Check
    if client_ip in blocked_ips:
        return {"status": "blocked", "message": "Your IP is permanently banned."}

    now = datetime.datetime.now()
    
    # 📍 3. Geolocation
    location = "Local Lab"
    try:
        geo = requests.get(f"http://ip-api.com/json/{client_ip}").json()
        if geo.get('status') == 'success':
            location = f"{geo.get('city')}, {geo.get('country')}"
    except:
        location = "Unknown"

    # 🧠 4. AI Logic
    attack_history[client_ip].append(now)
    attack_history[client_ip] = [t for t in attack_history[client_ip] if (now - t).total_seconds() < WINDOW_SECONDS]
    
    threat_level, attack_type = ("Low", "Scanning")
    if len(attack_history[client_ip]) >= THRESHOLD:
        threat_level, attack_type = ("High", "Brute Force")
    elif fax_number:
        threat_level, attack_type = ("Medium", "Bot Injection")

    # 📝 5. Create Log Entry & Save to Cloud
    log_entry = {
        "timestamp": now.strftime("%Y-%m-%d %H:%M:%S"),
        "ip": client_ip,
        "location": location,
        "username": username,
        "threat_level": threat_level,
        "attack_type": attack_type
    }
    
    # Save to MongoDB Atlas
    await logs_collection.insert_one(log_entry)

    # 🛡️ 6. Admin Override Logic
    if username == "janar_admin":
        return {"status": "accepted", "message": "Welcome, Admin!"}
    
    return {"status": "denied", "classification": attack_type}

@app.get("/logs")
async def get_logs():
    # Fetch latest 20 logs from the cloud database
    cursor = logs_collection.find().sort("_id", -1).limit(20)
    logs = []
    async for document in cursor:
        # 🛡️ FIX: Convert the ObjectId to a String so Flutter doesn't crash
        document["_id"] = str(document["_id"]) 
        logs.append(document)
    return logs

@app.get("/blacklist")
async def get_blacklist():
    return list(blocked_ips)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)