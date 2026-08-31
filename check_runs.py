import urllib.request
import json

url = 'https://api.github.com/repos/johnhari/secure/actions/runs?per_page=4'
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read().decode('utf-8'))
        for r in data.get('workflow_runs', []):
            name = r.get('name')
            run_id = r.get('id')
            status = r.get('status')
            conclusion = r.get('conclusion')
            commit_msg = r.get('head_commit', {}).get('message', '')[:45]
            print(f"Workflow: {name} | ID: {run_id} | Status: {status} | Conclusion: {conclusion} | Commit: {commit_msg}")
except Exception as e:
    print(f"Error fetching runs: {e}")
