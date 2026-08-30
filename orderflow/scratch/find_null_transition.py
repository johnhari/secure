path = r"c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\orderflow\lib\presentation\screens\chart_screen.dart"
with open(path, "rb") as f:
    content = f.read()

first_null = content.find(b'\x00')
print("First null byte index:", first_null)
if first_null != -1:
    print("Bytes before first null:")
    print(content[max(0, first_null-100):first_null])
    print("Bytes after first null:")
    print(content[first_null:first_null+100])
