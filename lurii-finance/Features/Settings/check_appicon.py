you run #!/usr/bin/env python3
"""
Script to check and diagnose AppIcon configuration issues in Xcode projects.
"""

import os
import json
import sys
from pathlib import Path

def find_assets_xcassets(start_path="."):
    """Find all Assets.xcassets directories."""
    assets = []
    for root, dirs, files in os.walk(start_path):
        if "Assets.xcassets" in dirs:
            assets.append(os.path.join(root, "Assets.xcassets"))
    return assets

def check_appicon_asset(assets_path):
    """Check AppIcon configuration in an Assets.xcassets directory."""
    appicon_path = os.path.join(assets_path, "AppIcon.appiconset")
    
    print(f"\n{'='*60}")
    print(f"Checking: {assets_path}")
    print(f"{'='*60}")
    
    if not os.path.exists(appicon_path):
        print("❌ AppIcon.appiconset NOT FOUND!")
        print(f"   Expected at: {appicon_path}")
        return False
    
    print("✅ AppIcon.appiconset directory exists")
    
    # Check Contents.json
    contents_json_path = os.path.join(appicon_path, "Contents.json")
    if not os.path.exists(contents_json_path):
        print("❌ Contents.json NOT FOUND in AppIcon.appiconset!")
        return False
    
    print("✅ Contents.json exists")
    
    # Read and parse Contents.json
    try:
        with open(contents_json_path, 'r') as f:
            contents = json.load(f)
    except Exception as e:
        print(f"❌ Error reading Contents.json: {e}")
        return False
    
    print("\n📋 Contents.json content:")
    print(json.dumps(contents, indent=2))
    
    # Check for images
    images = contents.get("images", [])
    if not images:
        print("\n❌ No images defined in Contents.json!")
        return False
    
    print(f"\n📊 Image slots defined: {len(images)}")
    
    # Check which images are present
    missing = []
    present = []
    
    for img in images:
        size = img.get("size", "?")
        scale = img.get("scale", "?")
        idiom = img.get("idiom", "?")
        filename = img.get("filename")
        
        if filename:
            filepath = os.path.join(appicon_path, filename)
            if os.path.exists(filepath):
                file_size = os.path.getsize(filepath)
                present.append(f"✅ {size}@{scale} ({idiom}): {filename} ({file_size} bytes)")
            else:
                missing.append(f"❌ {size}@{scale} ({idiom}): {filename} - FILE MISSING!")
        else:
            missing.append(f"⚠️  {size}@{scale} ({idiom}): No filename specified")
    
    print("\n📁 Image files:")
    for item in present:
        print(f"  {item}")
    
    if missing:
        print("\n⚠️  Missing or unspecified images:")
        for item in missing:
            print(f"  {item}")
    
    # List all files in the directory
    all_files = os.listdir(appicon_path)
    image_files = [f for f in all_files if f.lower().endswith(('.png', '.jpg', '.jpeg'))]
    
    print(f"\n📂 All files in AppIcon.appiconset: {len(all_files)}")
    for f in all_files:
        filepath = os.path.join(appicon_path, f)
        size = os.path.getsize(filepath)
        print(f"  - {f} ({size} bytes)")
    
    return len(present) > 0

def check_info_plist():
    """Check Info.plist for icon configuration."""
    print(f"\n{'='*60}")
    print("Checking Info.plist")
    print(f"{'='*60}")
    
    # Common locations for Info.plist
    possible_paths = [
        "Info.plist",
        "*/Info.plist",
        "lurii-finance/Info.plist",
    ]
    
    found = False
    for pattern in possible_paths:
        for plist_path in Path(".").glob(pattern):
            if plist_path.is_file():
                print(f"\n✅ Found Info.plist at: {plist_path}")
                found = True
                
                # Try to read it (it might be binary or XML)
                try:
                    with open(plist_path, 'rb') as f:
                        content = f.read(100)
                        if b'CFBundleIconFile' in content or b'CFBundleIconName' in content:
                            print("✅ Contains icon configuration keys")
                        else:
                            print("⚠️  No obvious icon keys found (file might be binary)")
                except Exception as e:
                    print(f"⚠️  Could not read plist: {e}")
    
    if not found:
        print("⚠️  Info.plist not found in common locations")

def generate_fix_script(assets_path):
    """Generate a script to help fix common issues."""
    print(f"\n{'='*60}")
    print("Fix Suggestions")
    print(f"{'='*60}")
    
    print("""
To fix AppIcon issues:

1. Make sure you have icon images at these sizes for macOS:
   - 16x16 (1x and 2x)
   - 32x32 (1x and 2x)
   - 128x128 (1x and 2x)
   - 256x256 (1x and 2x)
   - 512x512 (1x and 2x)

2. In Xcode:
   - Open Assets.xcassets
   - Select AppIcon
   - Drag your icon PNG files into the appropriate slots
   - Make sure ALL slots are filled (especially 512x512 and 1024x1024)

3. Clean and rebuild:
   - Product → Clean Build Folder (Cmd+Shift+K)
   - Delete app from /Applications if it exists
   - Rebuild and run

4. If still not working, check:
   - Project Settings → General → App Icon should be "AppIcon"
   - The icon files must be PNG format
   - The icon files must match the exact pixel dimensions
""")

def main():
    print("🔍 AppIcon Diagnostic Tool")
    print("="*60)
    
    # Find all Assets.xcassets
    assets_catalogs = find_assets_xcassets()
    
    if not assets_catalogs:
        print("❌ No Assets.xcassets directories found!")
        print("   Make sure you're running this script from your Xcode project directory.")
        sys.exit(1)
    
    print(f"\n✅ Found {len(assets_catalogs)} Assets.xcassets director(ies)")
    
    # Check each one
    any_valid = False
    for assets_path in assets_catalogs:
        if check_appicon_asset(assets_path):
            any_valid = True
    
    # Check Info.plist
    check_info_plist()
    
    # Generate fix suggestions
    if assets_catalogs:
        generate_fix_script(assets_catalogs[0])
    
    print("\n" + "="*60)
    if any_valid:
        print("✅ At least one valid AppIcon configuration found!")
        print("   If icon still not showing, try cleaning build and rebuilding.")
    else:
        print("⚠️  AppIcon configuration needs attention!")
    print("="*60)

if __name__ == "__main__":
    main()
