import urllib.request
import json
import sys

run_id = sys.argv[1] if len(sys.argv) > 1 else '33359280755'
url = f'https://api.github.com/repos/johnhari/secure/actions/runs/{run_id}/jobs'
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read().decode('utf-8'))
        for job in data.get('jobs', []):
            print(f"=== Job: {job['name']} (Conclusion: {job['conclusion']}) ===")
            for s in job.get('steps', []):
                print(f"  Step: {s['name']} -> Status: {s['status']} | Conclusion: {s['conclusion']}")
except Exception as e:
    print(f"Error: {e}")
