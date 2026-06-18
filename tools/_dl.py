import _compat  # noqa
import os
# Force-disable brotli so the flaky brotlicffi decoder is never used.
try:
    import urllib3.util.request as ureq
    ureq.ACCEPT_ENCODING = "gzip, deflate"
except Exception as e:
    print("patch1 warn", e)
try:
    import requests.utils as rutils
    rutils.DEFAULT_ACCEPT_ENCODING = "gzip, deflate"
except Exception as e:
    print("patch2 warn", e)
import sys
from huggingface_hub import snapshot_download
repo = sys.argv[1]
path = snapshot_download(repo, local_dir=f"models/{repo.split('/')[-1]}")
print("DOWNLOADED:", path)
import os
for f in sorted(os.listdir(path)): print("  ", f)
