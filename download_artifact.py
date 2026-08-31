import urllib.request
import json
import zipfile
import io

artifact_id = '9749760252' # iOS-Build-Log from run 33369918520
url = f'https://api.github.com/repos/johnhari/secure/actions/artifacts/{artifact_id}/zip'
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
try:
    with urllib.request.urlopen(req, timeout=15) as resp:
        content = resp.read()
        with zipfile.ZipFile(io.BytesIO(content)) as z:
            print("Files in artifact:", z.namelist())
            for name in z.namelist():
                text = z.read(name).decode('utf-8', errors='ignore')
                print(f"=== Last 100 lines of {name} ===")
                lines = text.strip().split('\n')
                print('\n'.join(lines[-100:]))
except Exception as e:
    print(f"Error: {e}")
