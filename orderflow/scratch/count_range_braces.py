
def count_range(start_line, end_line):
    with open(r'c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\orderflow\lib\presentation\screens\admin_panel_screen.dart', 'r', encoding='utf-8') as f:
        lines = f.readlines()
        content = "".join(lines[start_line-1:end_line])
        open_braces = content.count('{')
        close_braces = content.count('}')
        print(f"Lines {start_line}-{end_line}: Open: {open_braces}, Close: {close_braces}")

count_range(2694, 2982)
count_range(2983, 3058)
count_range(3059, 3230)
