with open(r'c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\orderflow\lib\presentation\screens\chart_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

for idx, line in enumerate(lines):
    if any(term in line for term in ['AssetImage', 'Image.asset', 'SvgPicture', 'assets/', 'png', 'jpg', 'svg', 'logo', 'watermark']):
        print(f"Line {idx+1}: {line.strip()}")
