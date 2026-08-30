import os
import json
import subprocess
import datetime
import re

class CodeGuardian:
    def __init__(self, config_path):
        with open(config_path, 'r') as f:
            self.config = json.load(f)
        self.report_data = {
            "summary": "",
            "issues": [],
            "stats": {},
            "risks": {
                "performance": [],
                "security": [],
                "architecture": [],
                "sports_integrity": []
            },
            "dead_code": []
        }

    def run_command(self, cmd):
        print(f"Running: {cmd}")
        try:
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=self.config.get("android_project_dir", "."))
            return result.returncode == 0, result.stdout, result.stderr
        except Exception as e:
            return False, "", str(e)

    def check_build(self):
        success, stdout, stderr = self.run_command("../gradlew assembleDebug")
        if not success:
            self.report_data["issues"].append({
                "type": "Critical Bug",
                "title": "Build Failure",
                "description": "Project failed to compile debug build.",
                "evidence": stderr[-500:],
                "confidence": "High"
            })
        return success

    def check_lint(self):
        success, stdout, stderr = self.run_command("../gradlew lintDebug")
        # Parsing lint reports would be complex here, so we just check for common patterns in stdout
        if "Lint found" in stdout:
            self.report_data["issues"].append({
                "type": "Quality",
                "title": "Lint Warnings Detected",
                "description": "Standard Android Lint found issues that should be addressed.",
                "confidence": "High"
            })

    def scan_codebase(self):
        print("Scanning codebase...")
        root = self.config.get("android_project_dir", ".")
        for dirpath, dirnames, filenames in os.walk(root):
            if any(ignore in dirpath for ignore in self.config.get("ignore_paths", [])):
                continue
            
            for filename in filenames:
                if filename.endswith(".kt") or filename.endswith(".java"):
                    file_path = os.path.join(dirpath, filename)
                    self.analyze_file(file_path)

    def analyze_file(self, path):
        with open(path, 'r') as f:
            lines = f.readlines()
        
        # Check 1: File size
        if len(lines) > self.config["thresholds"]["max_file_lines"]:
            self.report_data["risks"]["architecture"].append({
                "title": "Oversized File",
                "file": path,
                "description": f"File is too large ({len(lines)} lines). Consider splitting into smaller components.",
                "confidence": "High"
            })

        content = "".join(lines)

        # Check 2: Hardcoded strings (simple heuristic)
        if 'text = "' in content and not 'R.string' in content:
             self.report_data["issues"].append({
                "type": "UI Consistency",
                "title": "Hardcoded UI String",
                "file": path,
                "description": "Found hardcoded text in UI. Use string resources for localization.",
                "confidence": "Medium"
            })

        # Check 3: Missing error handling
        if "try {" in content and not "catch" in content: # Unusual but possible in some cases
             pass 
        if "catch (e: Exception)" in content and "Log.e" not in content and "//" in content:
             self.report_data["issues"].append({
                "type": "Fragility",
                "title": "Weak Error Handling",
                "file": path,
                "description": "Empty or silent catch block detected.",
                "confidence": "Medium"
            })

        # Check 4: Recomposition risks (simple search)
        if "@Composable" in content and "mutableStateOf" in content and "remember" not in content:
             self.report_data["risks"]["performance"].append({
                "title": "Unremembered State",
                "file": path,
                "description": "State created in @Composable without remember() will be lost on recomposition.",
                "confidence": "High"
            })

        # Check 5: Sports Integrity (PROHIBITED NON-SPORTS CONTENT)
        prohibited = ["movie", "tv show", "episode", "season", "watchlist", "cinema", "actor", "series", "anime", "manga"]
        for word in prohibited:
            if re.search(r'\b' + re.escape(word) + r'\b', content, re.IGNORECASE):
                # SPECIAL EXEMPTION: "season" is allowed if it looks like a sports year (e.g. 2024, 2025)
                if word == "season" and re.search(r'season\s*[=:]\s*\d{4}', content, re.IGNORECASE):
                    continue
                
                self.report_data["risks"]["sports_integrity"].append({
                    "title": "Non-Sports Content Violation",
                    "file": path,
                    "description": f"Found prohibited non-sports keyword: '{word}'. Fotty is a sports-only platform.",
                    "confidence": "High"
                })

        # Check 6: Architecture Violation (Specific Files)
        if "VodSourceResolver.kt" in path:
            self.report_data["risks"]["architecture"].append({
                "title": "Severe Architecture Violation",
                "file": path,
                "description": "VodSourceResolver detected. This component is designed for movies/TV (VOD) and should not exist in Fotty.",
                "confidence": "Critical"
            })

        # Check 7: Placeholder Data
        placeholders = ["john doe", "test player", "placeholder", "team a", "team b"]
        for p in placeholders:
            if p in content.lower():
                self.report_data["issues"].append({
                    "type": "Data Fidelity",
                    "title": "Placeholder Data Detected",
                    "file": path,
                    "description": f"Found placeholder data: '{p}'. Ensure real match data is used.",
                    "confidence": "High"
                })

    def generate_report(self):
        report_path = os.path.join(os.path.dirname(__file__), "..", self.config["report_path"])
        os.makedirs(os.path.dirname(report_path), exist_ok=True)

        with open(report_path, 'w') as f:
            f.write("# Code Guardian Report: Latest\n")
            f.write(f"Generated: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
            
            f.write("## Executive Summary\n")
            f.write(f"The Guardian has scanned the project. Found {len(self.report_data['issues'])} issues and {len(self.report_data['risks']['performance']) + len(self.report_data['risks']['architecture'])} risks.\n\n")

            f.write("## Top 10 Critical Issues\n")
            for i, issue in enumerate(self.report_data["issues"][:10]):
                f.write(f"### {i+1}. [{issue['type']}] {issue['title']}\n")
                f.write(f"- **Description**: {issue['description']}\n")
                if "file" in issue: f.write(f"- **File**: {issue['file']}\n")
                f.write(f"- **Confidence**: {issue['confidence']}\n\n")

            f.write("## Performance Risks\n")
            for risk in self.report_data["risks"]["performance"]:
                f.write(f"- **{risk['title']}** in `{risk['file']}`: {risk['description']}\n")

            f.write("\n## Architecture Risks\n")
            for risk in self.report_data["risks"]["architecture"]:
                f.write(f"- **{risk['title']}** in `{risk['file']}`: {risk['description']}\n")

            f.write("\n## Sports Integrity Risks (CRITICAL)\n")
            if not self.report_data["risks"]["sports_integrity"]:
                f.write("- ✅ No non-sports content detected.\n")
            else:
                for risk in self.report_data["risks"]["sports_integrity"]:
                    f.write(f"- **{risk['title']}** in `{risk['file']}`: {risk['description']}\n")

            f.write("\n## Do Not Change Yet (Risky Areas)\n")
            f.write("- **Player Logic**: Media3 implementation is sensitive to state timing.\n")
            f.write("- **P2P Resolver**: Complex threading and timeout logic.\n")
            
            f.write("\n## Next Steps\n")
            f.write("1. Review high-confidence UI issues.\n")
            f.write("2. Refactor oversized ViewModels.\n")
            f.write("3. Address lint warnings to improve code health.\n")

        print(f"Report generated at: {report_path}")

if __name__ == "__main__":
    guardian = CodeGuardian("config.json")
    # guardian.check_build() # Slow, enable in CI
    guardian.check_lint()
    guardian.scan_codebase()
    guardian.generate_report()
