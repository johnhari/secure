
def find_imbalance():
    with open(r'c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\orderflow\lib\presentation\screens\admin_panel_screen.dart', 'r', encoding='utf-8') as f:
        lines = f.readlines()
        balance = 0
        for i, line in enumerate(lines):
            for char in line:
                if char == '{': balance += 1
                if char == '}': balance -= 1
            if balance < 1 and i > 30: # After class declaration
                print(f"Balance became {balance} at line {i+1}: {line.strip()}")
                # break # find first

find_imbalance()
