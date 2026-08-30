import os
import re

def redact(text):
    patterns = [
        (r'api[_-]?key[:=]\s*[\'"][^\'"]+[\'"]', 'api_key: "[REDACTED]"'),
        (r'password[:=]\s*[\'"][^\'"]+[\'"]', 'password: "[REDACTED]"'),
        (r'token[:=]\s*[\'"][^\'"]+[\'"]', 'token: "[REDACTED]"'),
        (r'DEVELOPMENT_TEAM\s*=\s*\w+', 'DEVELOPMENT_TEAM = [REDACTED]')
    ]
    for pattern, replacement in patterns:
        text = re.sub(pattern, replacement, text, flags=re.IGNORECASE)
    return text

def aggregate():
    output_path = "docs/notebooklm/Fotty-Brain-V1.5.md"
    files_to_include = [
        "project.yml",
        "fotty_commercial_roadmap.md",
        "TESTFLIGHT_READINESS.md",
        "IOS_MANUAL_DEPLOY.md",
        "README.md",
        "docs/notebooklm/Fotty-Project-Memory.md"
    ]
    
    with open(output_path, "w") as out:
        out.write("# FOTTY MASTER KNOWLEDGE BASE (v1.5)\n")
        out.write("Generated on: 2026-05-08\n\n")
        
        for f in files_to_include:
            if os.path.exists(f):
                out.write(f"\n\n--- SOURCE: {f} ---\n\n")
                with open(f, "r") as src:
                    out.write(redact(src.read()))
            else:
                out.write(f"\n\n--- SOURCE: {f} (NOT FOUND) ---\n\n")
                
    print(f"Created {output_path}")

if __name__ == "__main__":
    aggregate()

def aggregate_code():
    output_path = "docs/notebooklm/Fotty-Brain-V1.5.md"
    core_files = [
        "Fotty/Core/Internal/P2PDataService.swift",
        "Fotty/Core/Internal/StreamManager.swift",
        "Fotty/Core/Security/StringObfuscator.swift",
        "FottyAndroid/app/src/main/java/com/pixelperfect/fotty/core/util/AppSecurityManager.kt"
    ]
    
    with open(output_path, "a") as out:
        out.write("\n\n# CORE ARCHITECTURE & LOGIC\n")
        for f in core_files:
            if os.path.exists(f):
                out.write(f"\n\n--- CORE SOURCE: {f} ---\n\n")
                with open(f, "r") as src:
                    # Just taking the first 200 lines to give context without hitting LM token limits too hard
                    lines = src.readlines()[:200]
                    out.write(redact("".join(lines)))
    print(f"Appended core logic to {output_path}")

if __name__ == "__main__":
    aggregate_code()
