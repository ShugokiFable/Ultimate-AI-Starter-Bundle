from __future__ import annotations

import json
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

from .config import load_config
from .service import ForgeService
from .version import VERSION


class ForgeGui(tk.Tk):
    def __init__(self, config_path: str | None = None):
        super().__init__()
        self.title(f"Skyrim Forge {VERSION} Automation Fabric")
        self.geometry("1250x760")
        self.service = ForgeService(load_config(config_path))
        self._build()

    def _build(self):
        top = ttk.Frame(self); top.pack(fill="x", padx=8, pady=8)
        for label, command in [
            ("Doctor", lambda: self._run(self.service.doctor)),
            ("Discover tools", lambda: self._run(self.service.discover)),
            ("Toolchain status", lambda: self._run(self.service.toolchain_status)),
            ("Scan tool ZIP/folder", self._tool_scan),
            ("Capabilities", lambda: self._run(lambda: self.service.capabilities(None))),
            ("Framework lint", self._lint),
            ("Build framework", self._framework_build),
            ("Papyrus analyze", self._papyrus_analyze),
            ("Papyrus compile", self._papyrus_compile),
            ("Native audit", self._native_audit),
            ("Validate FOMOD", self._fomod),
            ("Build FOMOD", self._fomod_build),
            ("Validate release", self._release),
            ("Audit Nexus release", self._nexus_audit),
            ("Build Nexus release", self._nexus_build),
            ("Run automation job", self._job),
        ]:
            ttk.Button(top, text=label, command=command).pack(side="left", padx=4)
        self.output = tk.Text(self, wrap="none", font=("Consolas", 10))
        self.output.pack(fill="both", expand=True, padx=8, pady=8)
        ttk.Label(self, text="Forge never invents permissions or signs a Nexus uploader attestation. Missing rights evidence blocks share-ready status.").pack(anchor="w", padx=8, pady=4)

    def _run(self, func):
        def worker():
            try: value = func()
            except Exception as exc: value = {"result": "FAIL", "error": type(exc).__name__, "message": str(exc)}
            text = json.dumps(value, indent=2, ensure_ascii=False, default=str)
            self.after(0, lambda: (self.output.delete("1.0", "end"), self.output.insert("1.0", text)))
        threading.Thread(target=worker, daemon=True).start()

    def _tool_scan(self):
        path = filedialog.askopenfilename(title="Select tool ZIP", filetypes=[("ZIP archive", "*.zip"), ("All files", "*")])
        if not path:
            path = filedialog.askdirectory(title="Select tool directory")
        if path: self._run(lambda: self.service.tool_scan(path))

    def _lint(self):
        path = filedialog.askdirectory()
        if path: self._run(lambda: self.service.lint([path]))

    def _framework_build(self):
        plan = filedialog.askopenfilename(title="Select Forge framework plan", filetypes=[("Framework plan", "*.json")])
        if not plan: return
        parent = filedialog.askdirectory(title="Select existing Forge workspace parent")
        if not parent: return
        output = str(Path(parent) / (Path(plan).stem + " Output"))
        if messagebox.askyesno("Forge approval", f"Build framework configuration under {output!r}?"):
            self._run(lambda: self.service.framework_build(plan, output, True))

    def _papyrus_analyze(self):
        scripts = list(filedialog.askopenfilenames(title="Select Papyrus sources", filetypes=[("Papyrus source", "*.psc")]))
        if scripts: self._run(lambda: self.service.papyrus_analyze(scripts, []))

    def _papyrus_compile(self):
        scripts = list(filedialog.askopenfilenames(title="Select Papyrus sources", filetypes=[("Papyrus source", "*.psc")]))
        if not scripts: return
        parent = filedialog.askdirectory(title="Select existing Forge workspace parent")
        if not parent: return
        output = str(Path(parent) / "Papyrus Compiled")
        if messagebox.askyesno("Forge approval", f"Compile {len(scripts)} Papyrus source(s) into {output!r} with the configured pinned compiler?"):
            self._run(lambda: self.service.papyrus_compile(scripts, output, [], None, True, True))

    def _native_audit(self):
        project = filedialog.askdirectory(title="Select CommonLibSSE-NG project")
        if project: self._run(lambda: self.service.native_audit(project))

    def _fomod(self):
        path = filedialog.askdirectory(title="Select FOMOD release root")
        if path: self._run(lambda: self.service.fomod_validate(path, True))

    def _fomod_build(self):
        plan = filedialog.askopenfilename(title="Select Forge FOMOD plan", filetypes=[("Forge FOMOD plan", "*.json")])
        if not plan: return
        source = filedialog.askdirectory(title="Select FOMOD source tree")
        if not source: return
        output = filedialog.askdirectory(title="Select existing Forge workspace parent")
        if not output: return
        name = Path(source).name + " FOMOD"
        approved = messagebox.askyesno("Forge approval", f"Create {name!r} under the selected workspace directory?")
        if approved: self._run(lambda: self.service.fomod_build(plan, source, str(Path(output) / name), True))

    def _release(self):
        path = filedialog.askdirectory()
        if path: self._run(lambda: self.service.release_validate(path))

    def _nexus_audit(self):
        plan = filedialog.askopenfilename(title="Select Nexus publication plan", filetypes=[("Nexus publication plan", "*.json")])
        if not plan: return
        release = filedialog.askdirectory(title="Select final release tree")
        if release: self._run(lambda: self.service.nexus_audit(plan, release))

    def _nexus_build(self):
        plan = filedialog.askopenfilename(title="Select Nexus publication plan", filetypes=[("Nexus publication plan", "*.json")])
        if not plan: return
        release = filedialog.askdirectory(title="Select final release tree")
        if not release: return
        parent = filedialog.askdirectory(title="Select existing Forge workspace parent")
        if not parent: return
        output = str(Path(parent) / (Path(release).name + " Nexus Publication"))
        approved = messagebox.askyesno("Forge approval", "Build the final public release tree, private rights audit, generated Nexus page and ZIP?")
        if approved: self._run(lambda: self.service.nexus_build(plan, release, output, True))

    def _job(self):
        path = filedialog.askopenfilename(filetypes=[("Forge JSON jobs", "*.json")])
        if not path: return
        approved = messagebox.askyesno("Forge approval", "Approve writes/external operations requested by this typed job?")
        self._run(lambda: self.service.automation_run(path, approved, True))


def run_gui(config_path: str | None = None) -> None:
    ForgeGui(config_path).mainloop()
