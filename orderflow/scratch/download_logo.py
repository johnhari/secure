import urllib.request
import urllib.error
import ssl
import sys

def download_logo():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    urls = [
        # Official TCS Blue Logo 500px PNG preview
        "https://upload.wikimedia.org/wikipedia/commons/thumb/9/99/TATA_Consultancy_Services_Logo_blue.svg/500px-TATA_Consultancy_Services_Logo_blue.svg.png",
        # Raw SVG
        "https://upload.wikimedia.org/wikipedia/commons/9/99/TATA_Consultancy_Services_Logo_blue.svg"
    ]

    headers = {
        "User-Agent": "AdvanceOrderFlow/1.0 (admin@advanceorderflow.com)",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.9",
        "Referer": "https://commons.wikimedia.org/wiki/File:TATA_Consultancy_Services_Logo_blue.svg"
    }

    success = False
    for url in urls:
        print(f"Trying download from: {url}")
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, context=ctx, timeout=10) as response:
                content = response.read()
                if b"<!DOCTYPE html>" in content or b"<html" in content or b"Wikimedia Error" in content:
                    print(f"  Failed: Response was an HTML page (error/block).")
                    continue
                
                if len(content) < 500:
                    print(f"  Failed: Content size too small ({len(content)} bytes).")
                    continue
                
                ext = ".png"
                if url.endswith(".svg"):
                    ext = ".svg"
                
                target_path = "assets/images/tcs_logo.png"
                if ext == ".svg":
                    target_path = "assets/images/tcs_logo.svg"
                    
                with open(target_path, "wb") as f:
                    f.write(content)
                print(f"  Success! Downloaded {len(content)} bytes to {target_path}")
                success = True
                break
        except urllib.error.URLError as e:
            print(f"  Failed: Network error: {e}")
        except Exception as e:
            print(f"  Failed: Unexpected error: {e}")

    if not success:
        print("Could not download TCS logo from any source.")
        sys.exit(1)

if __name__ == "__main__":
    download_logo()
