import os
import subprocess
import time
import logging
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger("BrainMonitor")

WATCH_PATHS = ["docs/notebooklm", "agent", ".cursor/rules"]
SYNC_SCRIPT = "tools/brain/embed_index.py"
DEBOUNCE_SECONDS = 5

class BrainHandler(FileSystemEventHandler):
    def __init__(self):
        self.last_sync = 0

    def on_modified(self, event):
        if event.is_directory:
            return
        
        # Debounce to prevent multiple rapid syncs
        current_time = time.time()
        if current_time - self.last_sync < DEBOUNCE_SECONDS:
            return

        logger.info(f"File change detected: {event.src_path}")
        self.run_sync()
        self.last_sync = time.time()

    def run_sync(self):
        logger.info("Starting Semantic Index Sync...")
        try:
            # Get OLLAMA_HOST from environment or default to local
            ollama_host = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434")
            env = os.environ.copy()
            env["OLLAMA_HOST"] = ollama_host
            
            result = subprocess.run(
                ["python3", SYNC_SCRIPT],
                capture_output=True,
                text=True,
                env=env,
                cwd="/app"
            )
            if result.returncode == 0:
                logger.info("Sync complete.")
                logger.debug(result.stderr)
            else:
                logger.error(f"Sync failed: {result.stderr}")
        except Exception as e:
            logger.error(f"Error running sync script: {e}")

if __name__ == "__main__":
    logger.info("Starting Fotty Brain Monitor...")
    event_handler = BrainHandler()
    observer = Observer()
    
    # We monitor the whole app root but filter in the handler
    observer.schedule(event_handler, path="/app", recursive=True)
    observer.start()
    
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
    observer.join()
