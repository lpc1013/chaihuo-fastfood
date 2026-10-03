"""即梦批量产图驱动（Tabbit 单标签页）。

  python tools/jmkit.py ping                     # 探页面/模型/比例/登录态
  python tools/jmkit.py submit  job.json         # 提交整批提示词（建议一次 ≤3 批）
  python tools/jmkit.py collect job.json         # 轮询结果区，下载 4 张预览
  python tools/jmkit.py hd      job.json         # 逐张点开大图取高清原件到 out/hd/
  python tools/jmkit.py sheet   job.json         # 拼联络表 + md5 查重

job.json：{"out":"E:/restauran/assets/incoming","ratio":"16:9","count":4,
           "batches":[{"tag":"plate_a","prompt":"..."}]}
"""
import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
DRIVER = HERE / "jm" / "driver.js"
SCRATCH = HERE / "_scratch"
SCRATCH.mkdir(parents=True, exist_ok=True)
TASK = os.environ.get("JM_TASK", "jmimg16")
CLI = Path(os.environ.get("LOCALAPPDATA", "")) / "Tabbit/LocalAgent/bin/tabbit-cli.exe"


def run_stage(job: dict, timeout_ms: int = 175000) -> dict:
    job = dict(job)
    js = DRIVER.read_text(encoding="utf-8")
    js = js.replace("__JOB__", json.dumps(job, ensure_ascii=False))
    js = js.replace("__STAGE__", json.dumps(job.get("stage", "")))
    tmp = SCRATCH / f"run_{job.get('stage')}_{job.get('stamp','x')}.js"
    tmp.write_text(js, encoding="utf-8")
    cmd = [str(CLI), "nodejs", "--task", TASK,
           "--request-id", f"{job.get('stage')}{job.get('stamp','x')}",
           "--timeout-ms", str(timeout_ms)]
    with open(tmp, "r", encoding="utf-8") as fh:
        out = subprocess.run(cmd, stdin=fh, capture_output=True, text=True,
                             encoding="utf-8", errors="replace")
    lines = [l for l in (out.stdout or "").splitlines() if l.strip().startswith("{")]
    if not lines:
        return {"status": "no-json", "stdout": (out.stdout or "")[-2000:], "stderr": (out.stderr or "")[-2000:]}
    return json.loads(lines[-1])


def main() -> int:
    stage = sys.argv[1]
    job = {"out": "E:/restauran/assets/incoming", "ratio": "16:9", "count": 4,
           "model": "Seedream 5.0 Lite", "batches": []}
    if len(sys.argv) > 2:
        p = Path(sys.argv[2])
        base = json.loads(p.read_text(encoding="utf-8"))
        if "out" in base:
            job.update({k: v for k, v in base.items() if k != "stage"})
        else:
            job["batches"] = base
    if len(sys.argv) > 3:
        keep = set(sys.argv[3].split(","))
        job["batches"] = [b for b in job["batches"] if b["tag"] in keep]
    job["stage"] = stage
    job["stamp"] = str(int(__import__("time").time()))
    if stage == "ping":
        job["batches"] = []
    if stage not in ("ping",) and not job["batches"]:
        print("no batches", file=sys.stderr)
        return 2
    Path(job["out"]).mkdir(parents=True, exist_ok=True)
    res = run_stage(job)
    print(json.dumps(res, ensure_ascii=False, indent=1))
    return 0 if res.get("status") == "succeeded" else 1


if __name__ == "__main__":
    sys.exit(main())
