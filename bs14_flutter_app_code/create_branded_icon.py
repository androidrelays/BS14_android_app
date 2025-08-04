#!/usr/bin/env python3
"""
Create a branded launch screen icon with BS14 and company name
"""

from PIL import Image, ImageDraw, ImageFont
import os

def create_branded_icon():
    # Create a 512x512 image with blue gradient background
    size = 512
    img = Image.new('RGBA', (size, size), (37, 99, 235, 255))  # Blue background
    draw = ImageDraw.Draw(img)
    
    # Try to use a system font, fallback to default
    try:
        # Try different font paths for Windows
        font_paths = [
            "C:/Windows/Fonts/arial.ttf",
            "C:/Windows/Fonts/calibri.ttf", 
            "arial.ttf",
            "calibri.ttf"
        ]
        
        title_font = None
        subtitle_font = None
        
        for font_path in font_paths:
            try:
                title_font = ImageFont.truetype(font_path, 120)
                subtitle_font = ImageFont.truetype(font_path, 28)
                break
            except:
                continue
                
        if title_font is None:
            title_font = ImageFont.load_default()
            subtitle_font = ImageFont.load_default()
            
    except:
        title_font = ImageFont.load_default()
        subtitle_font = ImageFont.load_default()
    
    # Draw "BS14" in large text
    title_text = "BS14"
    title_bbox = draw.textbbox((0, 0), title_text, font=title_font)
    title_width = title_bbox[2] - title_bbox[0]
    title_height = title_bbox[3] - title_bbox[1]
    title_x = (size - title_width) // 2
    title_y = (size - title_height) // 2 - 40
    
    # Draw title with shadow
    draw.text((title_x + 3, title_y + 3), title_text, fill=(0, 0, 0, 100), font=title_font)  # Shadow
    draw.text((title_x, title_y), title_text, fill=(255, 255, 255, 255), font=title_font)  # Main text
    
    # Draw "By Relport, Inc." subtitle
    subtitle_text = "By Relport, Inc."
    subtitle_bbox = draw.textbbox((0, 0), subtitle_text, font=subtitle_font)
    subtitle_width = subtitle_bbox[2] - subtitle_bbox[0]
    subtitle_x = (size - subtitle_width) // 2
    subtitle_y = title_y + title_height + 20
    
    # Draw subtitle with shadow
    draw.text((subtitle_x + 2, subtitle_y + 2), subtitle_text, fill=(0, 0, 0, 100), font=subtitle_font)  # Shadow
    draw.text((subtitle_x, subtitle_y), subtitle_text, fill=(200, 200, 200, 255), font=subtitle_font)  # Main text
    
    # Draw decorative lines
    line_y1 = subtitle_y - 15
    line_y2 = subtitle_y + 50
    line_start = size // 4
    line_end = 3 * size // 4
    
    draw.line([(line_start, line_y1), (line_end, line_y1)], fill=(255, 255, 255, 150), width=2)
    draw.line([(line_start, line_y2), (line_end, line_y2)], fill=(255, 255, 255, 150), width=2)
    
    return img

def main():
    try:
        print("Creating branded launch screen icon...")
        icon = create_branded_icon()
        
        # Save the icon
        output_path = "assets/icon/launch_screen_icon.png"
        icon.save(output_path, "PNG")
        print(f"✅ Branded icon saved to {output_path}")
        
        print("\nNext steps:")
        print("1. Run: flutter pub get")
        print("2. Run: flutter pub run flutter_native_splash:create")
        print("3. The branded launch screen will be generated!")
        
    except Exception as e:
        print(f"❌ Error creating icon: {e}")
        print("\nAlternative: Use the HTML generator:")
        print("1. Open assets/icon/launch_screen_branded.html in a browser")
        print("2. Click 'Generate Branded Launch Icon'")
        print("3. Click 'Download Launch Icon'")
        print("4. Save as 'launch_screen_icon.png' in assets/icon/")

if __name__ == "__main__":
    main()
