#!/usr/bin/env python3
"""Regenerates Sources/Core/Options.swift (country / language / exchange pickers) from the Context.dev OpenAPI spec.
Usage: Tools/gen-options.py [path/to/openapi.json]   (downloads https://docs.context.dev/openapi.json when omitted)"""
import json, sys, os, urllib.request

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if len(sys.argv) > 1:
    s = json.load(open(sys.argv[1]))
else:
    s = json.load(urllib.request.urlopen("https://docs.context.dev/openapi.json"))
C = s["components"]["schemas"]
PARAMS = s["components"].get("parameters", {})

def deep(x):
    if isinstance(x, dict):
        if "$ref" in x:
            name = x["$ref"].split("/")[-1]
            return deep(C[name] if x["$ref"].startswith("#/components/schemas") else PARAMS[name])
        return {k: deep(v) for k, v in x.items()}
    if isinstance(x, list):
        return [deep(i) for i in x]
    return x

ws = deep(s["paths"]["/web/search"]["post"]["requestBody"]["content"]["application/json"]["schema"])
countries = ws["properties"]["country"]["enum"]
langs = [v for v in ws["properties"]["languages"]["anyOf"] if v.get("type") == "array"][0]["items"]["enum"]
news = deep(s["paths"]["/news/search"]["post"]["requestBody"]["content"]["application/json"]["schema"])
fb = news["properties"]["filterBy"]["properties"]
ent = news["properties"]["searchBy"]["oneOf"][1]["properties"]["entity"]["oneOf"]
exch = [x for x in ent if "ticker" in x["properties"]][0]["properties"]["exchange"]["enum"]
bs = {p["name"]: p for p in map(deep, s["paths"]["/brand/search"]["get"]["parameters"])}

def arr(name, vals):
    return f"    static let {name}: [String] = [{', '.join(json.dumps(v) for v in vals)}]\n"

out = "// Generated from the Context.dev OpenAPI spec by Tools/gen-options.py. Do not edit by hand.\n\nenum Options {\n"
out += arr("webCountries", countries) + arr("webLanguages", langs)
out += arr("newsCountries", fb["sourceCountry"]["items"]["enum"]) + arr("newsLanguages", fb["articleLanguage"]["items"]["enum"])
out += arr("exchanges", exch)
out += arr("brandCountries", bs["country"]["schema"]["enum"]) + arr("brandLanguages", bs["language"]["schema"]["enum"])
out += "}\n"
open(os.path.join(root, "Sources/Core/Options.swift"), "w").write(out)
print("wrote Sources/Core/Options.swift")
