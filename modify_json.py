import json

with open("CashbackCounter/Models/CardTemplateFallback.swift", "r") as f:
    content = f.read()

prefix = 'let defaultCardTemplatesJSON = """\n'
suffix = '\n"""'

start_idx = content.find(prefix) + len(prefix)
end_idx = content.rfind(suffix)

json_str = content[start_idx:end_idx]

try:
    data = json.loads(json_str)
    for item in data:
        if "memo" not in item:
            item["memo"] = ""
    
    new_json_str = json.dumps(data, indent=2, ensure_ascii=False)
    
    new_content = content[:start_idx] + new_json_str + content[end_idx:]
    
    with open("CashbackCounter/Models/CardTemplateFallback.swift", "w") as f:
        f.write(new_content)
    print("Success")
except Exception as e:
    print(f"Error: {e}")

