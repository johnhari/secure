import urllib.request
import json
import sys

run_id = sys.argv[1] if len(sys.argv) > 1 else '33369391867'
url = f'https://api.github.com/repos/johnhari/secure/actions/runs/{run_id}/jobs'
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read().decode('utf-8'))
        for job in data.get('jobs', []):
            print(f"Job: {job['name']} | Conclusion: {job['conclusion']}")
            for s in job.get('steps', []):
                print(f"  Step: {s['name']} [{s['conclusion']}] (Duration: {s.get('started_at')} to {s.get('completed_at')})")
except Exception as e:
    print(f"Error: {e}")
