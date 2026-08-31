import urllib.request
import json
import sys

run_id = sys.argv[1] if len(sys.argv) > 1 else '33368795049'
url = f'https://api.github.com/repos/johnhari/secure/actions/runs/{run_id}/artifacts'
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read().decode('utf-8'))
        print(f"Total Artifacts for Run {run_id}: {data.get('total_count', 0)}")
        for a in data.get('artifacts', []):
            bytes_size = a['size_in_bytes']
            print(f"  [Artifact] Name: {a['name']} | Bytes: {bytes_size:,} ({bytes_size / 1024:.1f} KB) | ID: {a['id']}")
except Exception as e:
    print(f"Error: {e}")
