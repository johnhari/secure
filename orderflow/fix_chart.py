import sys
import re

path = r"c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\orderflow\lib\presentation\screens\chart_screen.dart"
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Pattern to find the broken Expanded/Row structure
pattern = r"(\s+)\),\n(\s+)\),\n(\s+)if \(isDesktop\) _buildDesktopDashboard\(selectedInstrument, isSuperuser\),"
replacement = r"\1),\n\2),\n\2    ),\n\2if (isDesktop) _buildDesktopDashboard(selectedInstrument, isSuperuser),"

# Try regex replace (handle both \n and \r\n)
new_content, count = re.subn(pattern, replacement, content)
if count == 0:
    # Try with \r\n
    pattern_rn = pattern.replace(r"\n", r"\r\n")
    new_content, count = re.subn(pattern_rn, replacement.replace(r"\n", r"\r\n"), content)

if count > 0:
    with open(path, 'w', encoding='utf-8') as f:
        f.write(new_content)
    print(f"Successfully patched chart_screen.dart (Count: {count})")
else:
    print("Could not find the target pattern in chart_screen.dart")
    # Let's try an even simpler search and replace
    simple_old = "if (isDesktop) _buildDesktopDashboard(selectedInstrument, isSuperuser),"
    simple_new = "),\n                                    if (isDesktop) _buildDesktopDashboard(selectedInstrument, isSuperuser),"
    if simple_old in content:
        content = content.replace(simple_old, simple_new)
        with open(path, 'w', encoding='utf-8') as f:
            f.write(content)
        print("Successfully patched chart_screen.dart (Simple)")
    elif simple_old.replace(' ', '') in content.replace(' ', ''):
         print("Found a variation of the target string, but whitespace mismatch.")
