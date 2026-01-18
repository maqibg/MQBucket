#!/usr/bin/env python3
import os
import sys
import requests

def get_release_info(repo, token):
    if not token:
        print("Error: GITHUB_TOKEN not provided", file=sys.stderr)
        sys.exit(1)

    headers = {'Authorization': f'token {token}'}
    url = f'https://api.github.com/repos/{repo}/releases/latest'

    r = requests.get(url, headers=headers)
    r.raise_for_status()
    data = r.json()

    print(f"=== {repo} ===")
    print(f"Version: {data['tag_name']}")
    print("Assets:")
    for asset in data['assets']:
        if asset['name'].endswith(('.exe', '.msi', '.zip')):
            print(f"  {asset['name']}|{asset['browser_download_url']}")
    print()

if __name__ == '__main__':
    token = sys.argv[1] if len(sys.argv) > 1 else os.getenv('GITHUB_TOKEN')

    repos = [
        'dyndynjyxa/aio-coding-hub',
        'mos1128/ccg-gateway'
    ]

    for repo in repos:
        try:
            get_release_info(repo, token)
        except Exception as e:
            print(f"Error fetching {repo}: {e}", file=sys.stderr)
