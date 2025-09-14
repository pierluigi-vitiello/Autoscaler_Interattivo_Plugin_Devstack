#!/usr/bin/env python3
import json, subprocess, sys
def run(c): return subprocess.check_output(c, text=True)
def curr(n):
    try:
        d=json.loads(run(["openstack","server","show",n,"-f","json"]))
        f=d.get("flavor","")
        if isinstance(f,dict): return f.get("original_name") or f.get("name") or ""
        if isinstance(f,str):  return f.split()[0] if f else ""
    except Exception: pass
    return ""
if __name__=="__main__": print(curr(sys.argv[1]) if len(sys.argv)>1 else "", end="")
