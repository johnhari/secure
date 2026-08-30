path = r"c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\orderflow\lib\presentation\screens\chart_screen.dart"
with open(path, "rb") as f:
    content = f.read()

# Let's search for "StockSearchDelegate" bytes
# Spaced characters would look like: b'c\x00l\x00a\x00s\x00s\x00' if it's UTF-16, or b'c l a s s ' if it's UTF-8 with spaces.
print("Length of content:", len(content))
# Look at the end of the file
end_chars = content[-2000:]
print("End of file bytes sample:")
print(end_chars[:200])
# Let's check if there are null bytes
print("Contains null bytes:", b'\x00' in content)
