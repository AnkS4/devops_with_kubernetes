import os
import socket
import subprocess
from fastapi import FastAPI, HTTPException
from fastapi.responses import PlainTextResponse
import httpx
from datetime import datetime, timezone
import uuid
from pathlib import Path

app = FastAPI()

# # Use the same shared volume path as the generator
# STATUS_FILE = Path("/app/shared/status.txt")
# REQUEST_COUNT_FILE = Path(os.getenv('SHARED_VOLUME_PATH', '/app/shared/request_count.txt'))

# def read_request_count():
#     try:
#         with REQUEST_COUNT_FILE.open('r') as f:
#             return int(f.read().strip() or 0)
#     except (FileNotFoundError, ValueError):
#         return 0

# Function to get ClusterIP using kubectl
async def get_cluster_ip():
    try:
        # Use subprocess to run kubectl command
        cmd = ["kubectl", "get", "svc", "-n", "ping-pong-ns", "ping-pong-svc", "-o", "jsonpath='{.spec.clusterIP}'"]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0 and result.stdout:
            # Remove quotes if present
            ip = result.stdout.strip("'\"")
            print(f"Retrieved ClusterIP: {ip}")
            return ip
        else:
            print(f"Failed to get ClusterIP: {result.stderr}")
            return None
    except Exception as e:
        print(f"Error getting ClusterIP: {e}")
        return None

# Function to get Pod IP using kubectl
async def get_pod_ip():
    try:
        # Use subprocess to run kubectl command
        cmd = ["kubectl", "get", "pods", "-n", "ping-pong-ns", "-l", "app=ping-pong", "-o", "jsonpath='{.items[0].status.podIP}'"]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0 and result.stdout:
            # Remove quotes if present
            ip = result.stdout.strip("'\"")
            print(f"Retrieved Pod IP: {ip}")
            return ip
        else:
            print(f"Failed to get Pod IP: {result.stderr}")
            return None
    except Exception as e:
        print(f"Error getting Pod IP: {e}")
        return None

async def read_request_count():
    # Try fully qualified service name (cross-namespace)
    try:
        print("Trying fully qualified service name")
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get("http://ping-pong-svc.ping-pong-ns.svc.cluster.local:1234/pongs")
            print(f"Response status: {response.status_code}")
            response.raise_for_status()
            data = response.json()
            print(f"Response data: {data}")
            return data["pongs"]
    except Exception as e:
        print(f"Error with fully qualified name: {e}")
    
    # Try service name with namespace
    try:
        print("Trying service name with namespace")
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get("http://ping-pong-svc.ping-pong-ns:1234/pongs")
            print(f"Response status: {response.status_code}")
            response.raise_for_status()
            data = response.json()
            print(f"Response data: {data}")
            return data["pongs"]
    except Exception as e:
        print(f"Error with namespace: {e}")
    
    # Try ClusterIP directly
    try:
        print("Trying ClusterIP directly")
        cluster_ip = await get_cluster_ip()
        if cluster_ip:
            async with httpx.AsyncClient(timeout=5.0) as client:
                response = await client.get(f"http://{cluster_ip}:1234/pongs")
                print(f"Response status: {response.status_code}")
                response.raise_for_status()
                data = response.json()
                print(f"Response data: {data}")
                return data["pongs"]
        else:
            print("No ClusterIP found")
    except Exception as e:
        print(f"Error with ClusterIP: {e}")
    
    # Try Pod IP directly
    try:
        print("Trying Pod IP directly")
        pod_ip = await get_pod_ip()
        if pod_ip:
            async with httpx.AsyncClient(timeout=5.0) as client:
                response = await client.get(f"http://{pod_ip}:8002/pongs")
                print(f"Response status: {response.status_code}")
                response.raise_for_status()
                data = response.json()
                print(f"Response data: {data}")
                return data["pongs"]
        else:
            print("No Pod IP found")
    except Exception as e:
        print(f"Error with Pod IP: {e}")
    
    # All connection attempts failed
    print("All connection attempts failed")
    return 0

@app.get("/")
def root():
    return {"message": "Log Server is running. Check /status for the latest log and ping-pong count."}

@app.get("/status", response_class=PlainTextResponse)
async def status():
    try:
        # Generate timestamp and random string (previously from file)
        now = datetime.now(timezone.utc)
        timestamp = now.strftime('%Y-%m-%dT%H:%M:%S.') + f"{now.microsecond // 1000:03d}Z"
        random_string = str(uuid.uuid4())
        status_message = f"{timestamp}: {random_string}."
        
        # Read ping-pong request count via HTTP
        request_count = await read_request_count()
        
        # Return plain text with actual newlines
        return f"{status_message}\nPing / Pongs: {request_count}"
    except Exception as e:
        print(f"Error in status endpoint: {e}")
        raise HTTPException(status_code=404, detail="Status not available yet.")
