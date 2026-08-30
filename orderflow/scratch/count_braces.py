
with open(r'c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\orderflow\lib\presentation\screens\admin_panel_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()
    open_braces = content.count('{')
    close_braces = content.count('}')
    print(f"Open: {open_braces}, Close: {close_braces}")
