import os
import sys
import re
import json
import time
import zipfile
import threading
import subprocess
import urllib.request
import urllib.error
import tkinter as tk
from tkinter import messagebox, simpledialog

ROOT_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_FILE = os.path.join(ROOT_DIR, ".build_studio_config.json")
BUILDS_DIR = os.path.join(ROOT_DIR, "builds")
PROJECT_DIR = os.path.join(ROOT_DIR, "orderflow")

for folder in ["ios", "macos", "android", "windows"]:
    os.makedirs(os.path.join(BUILDS_DIR, folder), exist_ok=True)

class BuildStudioGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("BIG SHOT ORDERFLOW - Multi-Platform Build Studio")
        self.root.geometry("1040x780")
        self.root.minsize(900, 700)
        self.root.configure(bg="#0b0f19")

        self.is_building = False
        self.config = self.load_config()

        self.setup_styles()
        self.create_widgets()
        self.auto_detect_git()

    def setup_styles(self):
        self.colors = {
            "bg": "#0b0f19",
            "card": "#131c2e",
            "card_hover": "#1e293b",
            "border": "#22314e",
            "cyan": "#00f0ff",
            "green": "#10b981",
            "purple": "#a855f7",
            "amber": "#f59e0b",
            "red": "#ef4444",
            "text": "#f8fafc",
            "text_dim": "#94a3b8",
            "console_bg": "#070b12",
            "console_text": "#38bdf8",
        }

    def load_config(self):
        if os.path.exists(CONFIG_FILE):
            try:
                with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception:
                pass
        return {"repo": "", "token": "", "branch": "main"}

    def save_config(self):
        repo_val = self.clean_repo_name(self.repo_entry.get().strip())
        self.config["repo"] = repo_val
        self.config["token"] = self.token_entry.get().strip()
        self.config["branch"] = self.branch_entry.get().strip() or "main"
        try:
            with open(CONFIG_FILE, "w", encoding="utf-8") as f:
                json.dump(self.config, f, indent=2)
            self.log("💾 Settings saved successfully.\n", "cyan")
        except Exception as e:
            self.log(f"⚠️ Failed to save config: {e}\n", "red")

    def clean_repo_name(self, raw):
        if not raw:
            return ""
        raw = raw.strip()
        match = re.search(r"github\.com[:/]([\w\-]+/[\w\-]+)", raw)
        if match:
            return match.group(1).removesuffix(".git")
        return raw.removesuffix(".git")

    def auto_detect_git(self):
        try:
            res = subprocess.run(["git", "branch", "--show-current"], cwd=ROOT_DIR, capture_output=True, text=True)
            curr_branch = res.stdout.strip()
            if curr_branch:
                self.branch_entry.delete(0, tk.END)
                self.branch_entry.insert(0, curr_branch)
        except Exception:
            pass

        try:
            res = subprocess.run(["git", "remote", "get-url", "origin"], cwd=ROOT_DIR, capture_output=True, text=True)
            url = res.stdout.strip()
            if url and not self.repo_entry.get().strip():
                clean = self.clean_repo_name(url)
                self.repo_entry.delete(0, tk.END)
                self.repo_entry.insert(0, clean)
        except Exception:
            pass

    def create_widgets(self):
        # Header Banner
        header = tk.Frame(self.root, bg=self.colors["card"], height=70, bd=0)
        header.pack(fill=tk.X, padx=0, pady=0)

        title_frame = tk.Frame(header, bg=self.colors["card"])
        title_frame.pack(side=tk.LEFT, padx=20, pady=12)

        title_label = tk.Label(
            title_frame,
            text="⚡ BIG SHOT ORDERFLOW BUILD STUDIO",
            font=("Segoe UI", 15, "bold"),
            fg=self.colors["cyan"],
            bg=self.colors["card"]
        )
        title_label.pack(anchor="w")

        subtitle = tk.Label(
            title_frame,
            text="One-Click Cloud & Native Compiler for iOS (.ipa), macOS (.dmg), Android (.apk) & Windows (.exe)",
            font=("Segoe UI", 9),
            fg=self.colors["text_dim"],
            bg=self.colors["card"]
        )
        subtitle.pack(anchor="w")

        # Top Action Buttons
        top_btn_frame = tk.Frame(header, bg=self.colors["card"])
        top_btn_frame.pack(side=tk.RIGHT, padx=20, pady=15)

        btn_new_repo = tk.Button(
            top_btn_frame,
            text="➕ Create GitHub Repo",
            font=("Segoe UI", 9, "bold"),
            bg="#1e293b",
            fg=self.colors["amber"],
            activebackground=self.colors["amber"],
            activeforeground="#000000",
            relief=tk.FLAT,
            padx=10,
            pady=6,
            cursor="hand2",
            command=self.open_new_repo_browser
        )
        btn_new_repo.pack(side=tk.LEFT, padx=4)

        btn_open_folder = tk.Button(
            top_btn_frame,
            text="📂 Open Builds Folder",
            font=("Segoe UI", 9, "bold"),
            bg="#1e293b",
            fg=self.colors["text"],
            activebackground=self.colors["cyan"],
            activeforeground="#000000",
            relief=tk.FLAT,
            padx=10,
            pady=6,
            cursor="hand2",
            command=self.open_builds_dir
        )
        btn_open_folder.pack(side=tk.LEFT, padx=4)

        btn_github = tk.Button(
            top_btn_frame,
            text="🌐 GitHub Actions",
            font=("Segoe UI", 9, "bold"),
            bg="#1e293b",
            fg=self.colors["cyan"],
            activebackground=self.colors["cyan"],
            activeforeground="#000000",
            relief=tk.FLAT,
            padx=10,
            pady=6,
            cursor="hand2",
            command=self.open_github_actions_browser
        )
        btn_github.pack(side=tk.LEFT, padx=4)

        # Main Container
        main_frame = tk.Frame(self.root, bg=self.colors["bg"])
        main_frame.pack(fill=tk.BOTH, expand=True, padx=20, pady=15)

        # Left Column
        left_col = tk.Frame(main_frame, bg=self.colors["bg"], width=530)
        left_col.pack(side=tk.LEFT, fill=tk.BOTH, expand=False, padx=(0, 10))

        self.create_config_card(left_col)
        self.create_platform_cards(left_col)

        # Right Column
        right_col = tk.Frame(main_frame, bg=self.colors["bg"])
        right_col.pack(side=tk.RIGHT, fill=tk.BOTH, expand=True, padx=(10, 0))

        self.create_console_card(right_col)

        # Bottom Status Bar
        self.status_bar = tk.Label(
            self.root,
            text="Ready • All systems operational",
            font=("Segoe UI", 9),
            fg=self.colors["green"],
            bg=self.colors["card"],
            anchor="w",
            padx=15,
            pady=6
        )
        self.status_bar.pack(fill=tk.X, side=tk.BOTTOM)

    def create_config_card(self, parent):
        card = tk.LabelFrame(
            parent,
            text=" ⚙️ GitHub Cloud Link (For iOS .IPA & macOS .DMG) ",
            font=("Segoe UI", 10, "bold"),
            fg=self.colors["cyan"],
            bg=self.colors["card"],
            bd=1,
            relief=tk.SOLID
        )
        card.pack(fill=tk.X, pady=(0, 10), ipady=4)

        f1 = tk.Frame(card, bg=self.colors["card"])
        f1.pack(fill=tk.X, padx=12, pady=3)
        tk.Label(f1, text="GitHub Repo (username/repo):", font=("Segoe UI", 9), fg=self.colors["text"], bg=self.colors["card"], width=27, anchor="w").pack(side=tk.LEFT)
        self.repo_entry = tk.Entry(f1, font=("Consolas", 9), bg="#0b0f19", fg=self.colors["cyan"], insertbackground="white", bd=1, relief=tk.SOLID)
        self.repo_entry.pack(side=tk.RIGHT, fill=tk.X, expand=True)
        self.repo_entry.insert(0, self.config.get("repo", ""))

        f2 = tk.Frame(card, bg=self.colors["card"])
        f2.pack(fill=tk.X, padx=12, pady=3)
        tk.Label(f2, text="Personal Token / PAT (Optional):", font=("Segoe UI", 9), fg=self.colors["text"], bg=self.colors["card"], width=27, anchor="w").pack(side=tk.LEFT)
        self.token_entry = tk.Entry(f2, font=("Consolas", 9), bg="#0b0f19", fg=self.colors["text"], insertbackground="white", bd=1, relief=tk.SOLID, show="*")
        self.token_entry.pack(side=tk.RIGHT, fill=tk.X, expand=True)
        self.token_entry.insert(0, self.config.get("token", ""))

        f3 = tk.Frame(card, bg=self.colors["card"])
        f3.pack(fill=tk.X, padx=12, pady=3)
        tk.Label(f3, text="Git Branch:", font=("Segoe UI", 9), fg=self.colors["text"], bg=self.colors["card"], width=27, anchor="w").pack(side=tk.LEFT)
        self.branch_entry = tk.Entry(f3, font=("Consolas", 9), bg="#0b0f19", fg=self.colors["text"], insertbackground="white", bd=1, relief=tk.SOLID, width=12)
        self.branch_entry.pack(side=tk.LEFT)
        self.branch_entry.insert(0, self.config.get("branch", "main"))

        btn_save = tk.Button(
            f3,
            text="💾 Save Link",
            font=("Segoe UI", 8, "bold"),
            bg="#2563eb",
            fg="white",
            relief=tk.FLAT,
            padx=10,
            pady=2,
            cursor="hand2",
            command=self.save_config
        )
        btn_save.pack(side=tk.RIGHT)

    def create_platform_cards(self, parent):
        cards_container = tk.Frame(parent, bg=self.colors["bg"])
        cards_container.pack(fill=tk.BOTH, expand=True)

        self.create_build_action_card(
            cards_container,
            icon="📱",
            title="Apple iOS (.IPA)",
            badge="CLOUD MAC COMPILER",
            badge_color=self.colors["purple"],
            desc="Builds iOS Release Package & Archive (.ipa) for iPhone / iPad / TestFlight.",
            btn_text="⚡ Build iOS (.IPA)",
            btn_color="#9333ea",
            command=lambda: self.start_cloud_build("build_ios.yml", "Orderflow-iOS-Release-IPA", "ios")
        )

        self.create_build_action_card(
            cards_container,
            icon="🍏",
            title="Apple macOS (.DMG)",
            badge="CLOUD MAC COMPILER",
            badge_color=self.colors["cyan"],
            desc="Builds native macOS Desktop App & Disk Image Installer (.dmg).",
            btn_text="⚡ Build macOS (.DMG)",
            btn_color="#0284c7",
            command=lambda: self.start_cloud_build("build_macos_dmg.yml", "Orderflow-macOS-Installer-DMG", "macos")
        )

        self.create_build_action_card(
            cards_container,
            icon="🤖",
            title="Android APK (.APK)",
            badge="NATIVE LOCAL BUILD",
            badge_color=self.colors["green"],
            desc="Builds Android Release APK installer directly on this Windows machine.",
            btn_text="⚡ Build Android (.APK)",
            btn_color="#059669",
            command=self.start_android_build
        )

        self.create_build_action_card(
            cards_container,
            icon="🪟",
            title="Windows Desktop (.EXE)",
            badge="NATIVE LOCAL BUILD",
            badge_color=self.colors["amber"],
            desc="Builds Windows 64-bit desktop executable release bundle.",
            btn_text="⚡ Build Windows (.EXE)",
            btn_color="#d97706",
            command=self.start_windows_build
        )

    def create_build_action_card(self, parent, icon, title, badge, badge_color, desc, btn_text, btn_color, command):
        card = tk.Frame(parent, bg=self.colors["card"], bd=1, relief=tk.SOLID)
        card.pack(fill=tk.X, pady=3, ipady=3)

        top_row = tk.Frame(card, bg=self.colors["card"])
        top_row.pack(fill=tk.X, padx=12, pady=(5, 2))

        lbl_title = tk.Label(
            top_row,
            text=f"{icon}  {title}",
            font=("Segoe UI", 10, "bold"),
            fg=self.colors["text"],
            bg=self.colors["card"]
        )
        lbl_title.pack(side=tk.LEFT)

        lbl_badge = tk.Label(
            top_row,
            text=f" {badge} ",
            font=("Segoe UI", 7, "bold"),
            fg=badge_color,
            bg="#0f172a",
            bd=1,
            relief=tk.SOLID
        )
        lbl_badge.pack(side=tk.RIGHT)

        lbl_desc = tk.Label(
            card,
            text=desc,
            font=("Segoe UI", 8),
            fg=self.colors["text_dim"],
            bg=self.colors["card"],
            anchor="w",
            justify=tk.LEFT
        )
        lbl_desc.pack(fill=tk.X, padx=12, pady=(0, 4))

        btn = tk.Button(
            card,
            text=btn_text,
            font=("Segoe UI", 9, "bold"),
            bg=btn_color,
            fg="white",
            activebackground=self.colors["cyan"],
            activeforeground="#000000",
            relief=tk.FLAT,
            padx=12,
            pady=3,
            cursor="hand2",
            command=command
        )
        btn.pack(anchor="e", padx=12, pady=(0, 5))

    def create_console_card(self, parent):
        card = tk.LabelFrame(
            parent,
            text=" 🖥️ Live Build Terminal & Process Monitor ",
            font=("Segoe UI", 10, "bold"),
            fg=self.colors["cyan"],
            bg=self.colors["card"],
            bd=1,
            relief=tk.SOLID
        )
        card.pack(fill=tk.BOTH, expand=True)

        ctl_frame = tk.Frame(card, bg=self.colors["card"])
        ctl_frame.pack(fill=tk.X, padx=8, pady=4)

        btn_analyze = tk.Button(
            ctl_frame,
            text="🔍 Run Flutter Analyze",
            font=("Segoe UI", 8),
            bg="#1e293b",
            fg=self.colors["text"],
            relief=tk.FLAT,
            padx=8,
            pady=2,
            cursor="hand2",
            command=self.run_analyze
        )
        btn_analyze.pack(side=tk.LEFT, padx=3)

        btn_test = tk.Button(
            ctl_frame,
            text="🧪 Run Unit Tests",
            font=("Segoe UI", 8),
            bg="#1e293b",
            fg=self.colors["text"],
            relief=tk.FLAT,
            padx=8,
            pady=2,
            cursor="hand2",
            command=self.run_tests
        )
        btn_test.pack(side=tk.LEFT, padx=3)

        btn_clear = tk.Button(
            ctl_frame,
            text="🧹 Clear",
            font=("Segoe UI", 8),
            bg="#1e293b",
            fg=self.colors["text_dim"],
            relief=tk.FLAT,
            padx=8,
            pady=2,
            cursor="hand2",
            command=self.clear_console
        )
        btn_clear.pack(side=tk.RIGHT, padx=3)

        text_frame = tk.Frame(card, bg=self.colors["console_bg"])
        text_frame.pack(fill=tk.BOTH, expand=True, padx=8, pady=(0, 8))

        self.console = tk.Text(
            text_frame,
            bg=self.colors["console_bg"],
            fg=self.colors["console_text"],
            insertbackground="white",
            font=("Consolas", 9),
            wrap=tk.WORD,
            bd=0,
            padx=8,
            pady=8
        )
        scrollbar = tk.Scrollbar(text_frame, command=self.console.yview, bg=self.colors["card"])
        self.console.configure(yscrollcommand=scrollbar.set)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.console.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        self.console.tag_config("cyan", foreground=self.colors["cyan"])
        self.console.tag_config("green", foreground=self.colors["green"])
        self.console.tag_config("purple", foreground=self.colors["purple"])
        self.console.tag_config("amber", foreground=self.colors["amber"])
        self.console.tag_config("red", foreground=self.colors["red"])
        self.console.tag_config("dim", foreground=self.colors["text_dim"])

        self.log("🚀 BIG SHOT Build Studio Initialized.\n", "cyan")
        self.log("Ready to compile iOS IPA, macOS DMG, Android APK, and Windows EXEs.\n\n", "dim")

    def log(self, text, tag="dim"):
        self.console.insert(tk.END, text, tag)
        self.console.see(tk.END)

    def clear_console(self):
        self.console.delete("1.0", tk.END)

    def set_status(self, text, color=None):
        if color is None:
            color = self.colors["green"]
        self.status_bar.config(text=text, fg=color)

    def open_builds_dir(self):
        try:
            os.startfile(BUILDS_DIR)
        except Exception as e:
            messagebox.showerror("Error", f"Could not open directory: {e}")

    def open_new_repo_browser(self):
        import webbrowser
        webbrowser.open("https://github.com/new?name=ADVANCEORDERFLOW&private=true")

    def open_github_actions_browser(self):
        repo = self.clean_repo_name(self.repo_entry.get().strip())
        import webbrowser
        if repo:
            webbrowser.open(f"https://github.com/{repo}/actions")
        else:
            webbrowser.open("https://github.com")

    # -------------------------------------------------------------
    # Cloud Build (iOS IPA & macOS DMG)
    # -------------------------------------------------------------
    def start_cloud_build(self, workflow_file, artifact_name, platform):
        if self.is_building:
            messagebox.showwarning("Busy", "A build process is already currently running.")
            return

        repo = self.clean_repo_name(self.repo_entry.get().strip())

        # If repo is empty, show interactive popup dialog
        if not repo:
            user_input = simpledialog.askstring(
                "GitHub Repository Required",
                "Enter your GitHub Repository name or URL:\n\nExample: yourusername/ADVANCEORDERFLOW\nOr: https://github.com/yourusername/ADVANCEORDERFLOW",
                parent=self.root
            )
            if user_input:
                repo = self.clean_repo_name(user_input.strip())
                self.repo_entry.delete(0, tk.END)
                self.repo_entry.insert(0, repo)
            else:
                self.log("⚠️ Cloud build cancelled. Please provide your GitHub repository.\n", "amber")
                return

        token = self.token_entry.get().strip()
        branch = self.branch_entry.get().strip() or "main"

        self.save_config()

        threading.Thread(
            target=self._cloud_build_worker,
            args=(repo, token, branch, workflow_file, artifact_name, platform),
            daemon=True
        ).start()

    def _ensure_git_remote(self, repo, token):
        if not repo:
            return
        
        target_url = f"https://github.com/{repo}.git"
        if token:
            target_url = f"https://{token}@github.com/{repo}.git"

        rem_check = subprocess.run(["git", "remote", "get-url", "origin"], cwd=ROOT_DIR, capture_output=True, text=True)
        if rem_check.returncode != 0:
            self.log(f"🔗 Setting Git remote 'origin' -> https://github.com/{repo}.git\n", "dim")
            subprocess.run(["git", "remote", "add", "origin", target_url], cwd=ROOT_DIR, capture_output=True)
        else:
            subprocess.run(["git", "remote", "set-url", "origin", target_url], cwd=ROOT_DIR, capture_output=True)

    def _cloud_build_worker(self, repo, token, branch, workflow_file, artifact_name, platform):
        self.is_building = True
        self.set_status(f"🚀 Pushing & Triggering {platform.upper()} Cloud Build...", self.colors["amber"])

        self.log(f"\n======================================================\n", "cyan")
        self.log(f"  STARTING CLOUD BUILD: {platform.upper()} ({workflow_file})\n", "cyan")
        self.log(f"======================================================\n", "cyan")

        # Ensure Git remote
        self._ensure_git_remote(repo, token)

        # Step 1: Git Push
        self.log("📦 Step 1: Syncing and pushing workspace to GitHub...\n", "amber")
        try:
            subprocess.run(["git", "branch", "-M", branch], cwd=ROOT_DIR, capture_output=True, text=True)
            subprocess.run(["git", "add", "."], cwd=ROOT_DIR, capture_output=True, text=True)
            subprocess.run(["git", "commit", "-m", f"Auto build {platform.upper()} via Build Studio"], cwd=ROOT_DIR, capture_output=True, text=True)
            
            push_res = subprocess.run(["git", "push", "-u", "origin", branch], cwd=ROOT_DIR, capture_output=True, text=True)
            
            if push_res.returncode == 0:
                self.log("✅ Git push successful! Workflows updated on GitHub.\n", "green")
            else:
                self.log(f"ℹ️ Git Push result: {push_res.stderr or push_res.stdout}\n", "dim")
        except Exception as e:
            self.log(f"⚠️ Git error: {e}\n", "amber")

        if not token:
            self.log("\nℹ️ Workspace pushed to GitHub!\n", "green")
            self.log(f"👉 Opening GitHub Actions in browser to run & download: https://github.com/{repo}/actions\n", "cyan")
            import webbrowser
            webbrowser.open(f"https://github.com/{repo}/actions")
            self.is_building = False
            self.set_status("Cloud Workflow Ready on GitHub", self.colors["green"])
            return

        # Step 2: Trigger GitHub Workflow Dispatch via API
        self.log(f"⚡ Step 2: Triggering '{workflow_file}' via GitHub REST API...\n", "amber")
        headers = {
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "User-Agent": "Orderflow-BuildStudio"
        }

        dispatch_url = f"https://api.github.com/repos/{repo}/actions/workflows/{workflow_file}/dispatches"
        req_data = json.dumps({"ref": branch}).encode("utf-8")

        try:
            req = urllib.request.Request(dispatch_url, data=req_data, headers=headers, method="POST")
            with urllib.request.urlopen(req) as resp:
                if resp.status in (200, 204):
                    self.log("✅ Workflow triggered on GitHub Actions!\n", "green")
        except Exception as e:
            self.log(f"⚠️ API Dispatch request: {e}\n", "amber")

        # Step 3: Polling for run status
        self.log("⏳ Step 3: Waiting for Apple Mac runner to compile in the cloud (~3 mins)...\n", "dim")
        runs_url = f"https://api.github.com/repos/{repo}/actions/runs?per_page=5"

        for attempt in range(45):
            time.sleep(10)
            try:
                req = urllib.request.Request(runs_url, headers=headers)
                with urllib.request.urlopen(req) as resp:
                    data = json.loads(resp.read().decode("utf-8"))
                    workflow_runs = data.get("workflow_runs", [])
                    if workflow_runs:
                        latest_run = workflow_runs[0]
                        run_id = latest_run.get("id")
                        status = latest_run.get("status")
                        conclusion = latest_run.get("conclusion")
                        
                        self.log(f"  [Elapsed: {attempt*10}s] Status: {status.upper()} | Conclusion: {str(conclusion).upper()}\n", "dim")
                        self.set_status(f"Cloud Build: {status.upper()}...", self.colors["amber"])

                        if status == "completed":
                            if conclusion == "success":
                                self.log("\n🎉 Cloud Build Completed Successfully!\n", "green")
                                self._download_artifact(repo, token, run_id, artifact_name, platform, headers)
                            else:
                                self.log(f"\n❌ Cloud Build finished with status: {conclusion}\n", "red")
                            break
            except Exception as e:
                self.log(f"  Polling: {e}\n", "dim")

        self.is_building = False
        self.set_status("Ready", self.colors["green"])

    def _download_artifact(self, repo, token, run_id, artifact_name, platform, headers):
        self.log("📥 Step 4: Downloading compiled build artifact...\n", "amber")
        artifacts_url = f"https://api.github.com/repos/{repo}/actions/runs/{run_id}/artifacts"

        try:
            req = urllib.request.Request(artifacts_url, headers=headers)
            with urllib.request.urlopen(req) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                artifacts = data.get("artifacts", [])
                
                target_art = None
                for art in artifacts:
                    if art.get("name") == artifact_name or artifact_name.lower() in art.get("name", "").lower():
                        target_art = art
                        break

                if not target_art and artifacts:
                    target_art = artifacts[0]

                if target_art:
                    download_url = target_art.get("archive_download_url")
                    out_zip = os.path.join(BUILDS_DIR, platform, "artifact.zip")
                    
                    self.log(f"Downloading {target_art.get('name')} ({target_art.get('size_in_bytes', 0) // 1024} KB)...\n", "cyan")
                    
                    req_dl = urllib.request.Request(download_url, headers=headers)
                    with urllib.request.urlopen(req_dl) as dl_resp, open(out_zip, "wb") as out_f:
                        out_f.write(dl_resp.read())

                    with zipfile.ZipFile(out_zip, 'r') as zip_ref:
                        zip_ref.extractall(os.path.join(BUILDS_DIR, platform))

                    os.remove(out_zip)
                    self.log(f"✅ Extracted to: {os.path.join(BUILDS_DIR, platform)}\n", "green")
                    self.set_status(f"SUCCESS: {platform.upper()} Saved to Builds Folder!", self.colors["green"])
                    
                    os.startfile(os.path.join(BUILDS_DIR, platform))
                else:
                    self.log("⚠️ No artifact found in completed run.\n", "amber")
        except Exception as e:
            self.log(f"⚠️ Artifact download error: {e}\n", "red")

    # -------------------------------------------------------------
    # Local Native Builds (Android APK & Windows EXE)
    # -------------------------------------------------------------
    def start_android_build(self):
        if self.is_building:
            messagebox.showwarning("Busy", "A build process is already currently running.")
            return

        threading.Thread(target=self._run_command_in_console, args=(
            ["flutter", "build", "apk", "--release"],
            "Android APK (.apk)",
            lambda: self._copy_artifact_and_open(
                os.path.join(PROJECT_DIR, "build", "app", "outputs", "flutter-apk", "app-release.apk"),
                os.path.join(BUILDS_DIR, "android", "Orderflow-Android-Release.apk"),
                os.path.join(BUILDS_DIR, "android")
            )
        ), daemon=True).start()

    def start_windows_build(self):
        if self.is_building:
            messagebox.showwarning("Busy", "A build process is already currently running.")
            return

        threading.Thread(target=self._run_command_in_console, args=(
            ["flutter", "build", "windows", "--release"],
            "Windows Desktop (.exe)",
            lambda: self._open_dir(os.path.join(PROJECT_DIR, "build", "windows", "x64", "runner", "Release"))
        ), daemon=True).start()

    def run_analyze(self):
        threading.Thread(target=self._run_command_in_console, args=(
            ["flutter", "analyze", "--no-fatal-warnings", "--no-fatal-infos"],
            "Flutter Analyze",
            None
        ), daemon=True).start()

    def run_tests(self):
        threading.Thread(target=self._run_command_in_console, args=(
            ["flutter", "test"],
            "Unit Tests",
            None
        ), daemon=True).start()

    def _run_command_in_console(self, cmd, label, on_success):
        self.is_building = True
        self.set_status(f"Building {label}...", self.colors["amber"])
        self.log(f"\n======================================================\n", "cyan")
        self.log(f"  RUNNING: {' '.join(cmd)}\n", "cyan")
        self.log(f"======================================================\n", "cyan")

        try:
            proc = subprocess.Popen(
                cmd,
                cwd=PROJECT_DIR,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                shell=True,
                bufsize=1
            )

            for line in proc.stdout:
                tag = "dim"
                if "error" in line.lower():
                    tag = "red"
                elif "success" in line.lower() or "passed" in line.lower():
                    tag = "green"
                elif "warning" in line.lower():
                    tag = "amber"
                self.log(line, tag)

            proc.wait()

            if proc.returncode == 0:
                self.log(f"\n🎉 {label} COMPLETED SUCCESSFULLY!\n", "green")
                self.set_status(f"Ready • {label} Success", self.colors["green"])
                if on_success:
                    on_success()
            else:
                self.log(f"\n❌ {label} finished with exit code {proc.returncode}\n", "red")
                self.set_status(f"Error building {label}", self.colors["red"])
        except Exception as e:
            self.log(f"⚠️ Execution failed: {e}\n", "red")
            self.set_status("Error", self.colors["red"])
        finally:
            self.is_building = False

    def _copy_artifact_and_open(self, src, dst, open_path):
        try:
            if os.path.exists(src):
                import shutil
                shutil.copy2(src, dst)
                self.log(f"📁 Copied release artifact to: {dst}\n", "green")
                os.startfile(open_path)
            else:
                self.log(f"⚠️ Source file not found: {src}\n", "amber")
        except Exception as e:
            self.log(f"⚠️ Copy error: {e}\n", "red")

    def _open_dir(self, path):
        try:
            if os.path.exists(path):
                os.startfile(path)
        except Exception:
            pass

if __name__ == "__main__":
    root = tk.Tk()
    app = BuildStudioGUI(root)
    root.mainloop()
