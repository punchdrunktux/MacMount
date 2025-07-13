# App Icon Generation Guide

This directory contains the app icon configuration for MacMount. Currently, placeholder icons are needed.

## Required Icon Sizes

The following icon sizes are required for macOS applications:

- 16x16 pixels (1x and 2x)
- 32x32 pixels (1x and 2x)
- 128x128 pixels (1x and 2x)
- 256x256 pixels (1x and 2x)
- 512x512 pixels (1x and 2x)

## Icon Design Suggestions

For a network drive mapper application, consider these design elements:

1. **Network/Connection Symbol**: Interconnected nodes or network topology
2. **Drive/Storage Symbol**: Hard drive or folder icon
3. **Connection Status**: Green dot or checkmark for connected state
4. **Color Scheme**: Professional blue/gray tones typical of system utilities

## Generating Icons

You can generate icons using:

1. **macOS iconutil**: Convert from iconset to icns format
2. **ImageMagick**: Create different sizes from a master 1024x1024 image
3. **Professional Tools**: Sketch, Figma, or Adobe Illustrator

### Quick Generation Script

```bash
# Assuming you have a 1024x1024 master icon
sips -z 16 16     icon_1024x1024.png --out icon_16x16.png
sips -z 32 32     icon_1024x1024.png --out icon_16x16@2x.png
sips -z 32 32     icon_1024x1024.png --out icon_32x32.png
sips -z 64 64     icon_1024x1024.png --out icon_32x32@2x.png
sips -z 128 128   icon_1024x1024.png --out icon_128x128.png
sips -z 256 256   icon_1024x1024.png --out icon_128x128@2x.png
sips -z 256 256   icon_1024x1024.png --out icon_256x256.png
sips -z 512 512   icon_1024x1024.png --out icon_256x256@2x.png
sips -z 512 512   icon_1024x1024.png --out icon_512x512.png
sips -z 1024 1024 icon_1024x1024.png --out icon_512x512@2x.png
```

## Placeholder Icon

Until proper icons are created, the app will use the default macOS application icon.