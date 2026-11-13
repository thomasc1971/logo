#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Rebuild HTML and PDF for PICCOLINE Mikro-Logo Brugervejledning (April 1985).

Usage:
  python3 docs/manual/build.py
"""

import os
import re
import subprocess
import sys

MANUAL_DIR = os.path.dirname(os.path.abspath(__file__))
MD_FILE = os.path.join(MANUAL_DIR, "PICCOLINE_Mikro-Logo_Brugervejledning_apr1985.md")
HTML_FILE = os.path.join(MANUAL_DIR, "PICCOLINE_Mikro-Logo_Brugervejledning_apr1985.html")
PDF_FILE = os.path.join(MANUAL_DIR, "PICCOLINE_Mikro-Logo_Brugervejledning_apr1985.pdf")

def get_chap_title(tag):
    if tag.startswith("Side "):
        num_str = tag[5:].strip()
        if num_str in ["i", "ii"]:
            return "INDHOLDSFORTEGNELSE"
        n = int(num_str)
        if n == 1:
            return "1. INDLEDNING"
        elif n == 2:
            return "2. INTRODUKTION TIL LOGO"
        elif 3 <= n <= 6:
            return "3. SKÆRMEN"
        elif 7 <= n <= 30:
            return "4. SÆTNINGER"
        elif 31 <= n <= 42:
            return "5. KOMMANDOER"
        elif 43 <= n <= 44:
            return "6. OVERVÅGNING AF UDFØRELSE AF SÆTNINGER"
        elif 45 <= n <= 47:
            return "A. FORSKELLE TIL MIKRO-LOGO PÅ PICCOLO"
        elif 48 <= n <= 57:
            return "B. DISTRIBUTIONSDISKETTEN"
        elif 58 <= n <= 63:
            return "C. LÆSEVEJLEDNING FOR BEGYNDERE"
        elif 64 <= n <= 66:
            return "D. ASCII TEGNSÆTTET"
        elif 67 <= n <= 72:
            return "E. FEJLMEDDELELSER"
        elif 73 <= n <= 75:
            return "F. OVERSIGT OVER SÆTNINGER OG KOMMANDOER"
        elif 76 <= n <= 80:
            return "G. REGISTRE"
        elif 81 <= n <= 82:
            return "LÆSERBEMÆRKNINGER"
    return ""

def build():
    print(f"Reading {MD_FILE}...")
    with open(MD_FILE, encoding="utf-8") as f:
        full_text = f.read()

    parts = re.split(r'<!--\s*(Side\s+[0-9ivxlcdm]+|Titelblad|Rygmærke|Fanebladsoversigt|Kolofon)\s*-->', full_text)

    html_pages = []
    seen_ids = set()

    for i in range(1, len(parts), 2):
        tag = parts[i].strip()
        md_content = parts[i+1].strip()

        # Remove horizontal rules between pages
        lines = md_content.splitlines()
        cleaned_lines = [l for l in lines if l.strip() != "---"]
        md_clean = "\n".join(cleaned_lines).strip()

        # Render markdown to HTML with Pandoc
        p = subprocess.run(
            ["pandoc", "-f", "markdown", "-t", "html5"],
            input=md_clean,
            text=True,
            capture_output=True,
            check=True
        )
        body_html = p.stdout.strip()

        # Deduplicate any ids generated inside body_html
        def replace_id(match):
            orig_id = match.group(1)
            new_id = orig_id
            counter = 1
            while new_id in seen_ids:
                new_id = f"{orig_id}-{counter}"
                counter += 1
            seen_ids.add(new_id)
            return f'id="{new_id}"'

        body_html = re.sub(r'id="([^"]+)"', replace_id, body_html)

        if tag.startswith("Side "):
            page_id = tag.lower().replace(" ", "-")
        else:
            page_id = f"page-{tag.lower().replace(' ', '-')}"

        counter = 1
        orig_page_id = page_id
        while page_id in seen_ids:
            page_id = f"{orig_page_id}-{counter}"
            counter += 1
        seen_ids.add(page_id)

        chap_title = get_chap_title(tag)

        extra_classes = []
        if tag == "Titelblad":
            extra_classes.append("cover")
        elif tag in ["Side i", "Side ii"]:
            extra_classes.append("toc-p")
        elif tag in ["Rygmærke", "Fanebladsoversigt", "Kolofon"]:
            extra_classes.append("front-matter")
        elif tag.startswith("Side "):
            extra_classes.append("body-p")

        is_odd = True
        page_num_str = ""
        if tag.startswith("Side "):
            num_part = tag[5:].strip()
            page_num_str = num_part
            if num_part.isdigit():
                n = int(num_part)
                is_odd = (n % 2 != 0)
            elif num_part in ["i", "ii"]:
                is_odd = (num_part == "i")

        if is_odd:
            left_header = "MIKRO-LOGO"
            right_header = chap_title
            left_footer = "A/S Regnecentralen"
            right_footer = f"Side {page_num_str}" if page_num_str else ""
        else:
            left_header = chap_title
            right_header = "MIKRO-LOGO"
            left_footer = f"Side {page_num_str}" if page_num_str else ""
            right_footer = "A/S Regnecentralen"

        page_header_screen = ""
        page_footer_screen = ""
        if chap_title:
            page_header_screen = f'<div class="page-header-screen"><span>{left_header}</span><span>{right_header}</span></div>'
        if page_num_str:
            page_footer_screen = f'<div class="page-footer-screen"><span>{left_footer}</span><span>{right_footer}</span></div>'

        page_tag_html = f'<div class="page-tag" data-chap="{chap_title}" data-pnum="{page_num_str}"></div>'

        classes_str = " ".join(["book-page"] + extra_classes)
        page_html = f"""<div class="{classes_str}" id="{page_id}">
  {page_tag_html}
  {page_header_screen}
  <div class="page-content">
{body_html}
  </div>
  {page_footer_screen}
</div>"""
        html_pages.append(page_html)

    full_html = f"""<!DOCTYPE html>
<html lang="da">
<head>
<meta charset="utf-8">
<title>PICCOLINE Mikro-Logo — Brugervejledning (April 1985)</title>
<link rel="stylesheet" href="style.css">
</head>
<body>
{''.join(html_pages)}
</body>
</html>
"""

    print(f"Writing {HTML_FILE}...")
    with open(HTML_FILE, "w", encoding="utf-8") as f:
        f.write(full_html)

    print(f"Compiling {PDF_FILE} via weasyprint...")
    subprocess.run(
        ["weasyprint", HTML_FILE, PDF_FILE],
        check=True
    )
    print("Build complete!")

if __name__ == "__main__":
    build()
