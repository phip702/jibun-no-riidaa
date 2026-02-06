import json

# Paths
input_file = "berserk_06.mokuro"        # your current .mokuro
output_file = "berserk_06_legacy.mokuro"  # output for web reader

# Load original .mokuro
with open(input_file, "r", encoding="utf-8") as f:
    data = json.load(f)

# Build legacy format
legacy_pages = []
for i, page in enumerate(data.get("pages", []), start=1):
    filename = f"{i:03}.png"  # 001.png, 002.png, etc.
    legacy_pages.append({
        "src": filename,
        "async": True,
        "text": ""  # optional: can extract OCR text here later
    })

# Save legacy .mokuro
with open(output_file, "w", encoding="utf-8") as f:
    json.dump(legacy_pages, f, ensure_ascii=False, indent=2)

print(f"Legacy .mokuro saved to {output_file}")
