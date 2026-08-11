#!/usr/bin/env python3
"""
Generate HTML sisters for Assert.IQ documentation markdown files.

Converts markdown files to searchable, styled HTML for publication.
Generates from both README markdown files and instruction files.
"""

import json
import os
import re
from pathlib import Path
from datetime import datetime

class DocumentationGenerator:
    def __init__(self, workspace_root="."):
        self.workspace_root = Path(workspace_root)
        self.docs_source = [
            "README.assert-iq.md",
            ".github/instructions/qi-foundation.instructions.md",
            ".github/instructions/qi-oracle.instructions.md",
            ".github/instructions/qi-signal-emission.instructions.md",
            ".github/instructions/qi-test-design.instructions.md",
            ".github/instructions/qi-manual-test-design.instructions.md",
            ".github/instructions/qi-traceability.instructions.md",
        ]
        self.html_output_dir = self.workspace_root / "docs" / "html"
        self.search_index = {}
        
    def markdown_to_html(self, markdown_content, title):
        """Convert markdown to basic HTML."""
        html = f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{title}</title>
    <style>
        body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
                line-height: 1.6; max-width: 900px; margin: 0 auto; padding: 20px; color: #333; }}
        h1, h2, h3 {{ color: #2c3e50; border-bottom: 1px solid #e1e4e8; padding-bottom: 0.3em; }}
        h1 {{ border-bottom: 2px solid #0366d6; }}
        code {{ background: #f6f8fa; padding: 2px 6px; border-radius: 3px; font-family: monospace; }}
        pre {{ background: #f6f8fa; padding: 12px; border-radius: 6px; overflow-x: auto; }}
        .meta {{ color: #666; font-size: 0.9em; margin-bottom: 20px; }}
        table {{ border-collapse: collapse; width: 100%; }}
        th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
        th {{ background: #f6f8fa; }}
        .search-highlight {{ background: #fff8cc; }}
        a {{ color: #0366d6; text-decoration: none; }}
        a:hover {{ text-decoration: underline; }}
    </style>
</head>
<body>
    <h1>{title}</h1>
    <div class="meta">Generated: {datetime.now().strftime("%Y-%m-%d %H:%M:%S UTC")}</div>
"""
        
        # Simple markdown to HTML conversion
        html_body = markdown_content
        html_body = re.sub(r'^### (.*?)$', r'<h3>\1</h3>', html_body, flags=re.MULTILINE)
        html_body = re.sub(r'^## (.*?)$', r'<h2>\1</h2>', html_body, flags=re.MULTILINE)
        html_body = re.sub(r'^# (.*?)$', r'<h1>\1</h1>', html_body, flags=re.MULTILINE)
        html_body = re.sub(r'`([^`]+)`', r'<code>\1</code>', html_body)
        html_body = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'<a href="\2">\1</a>', html_body)
        html_body = re.sub(r'\n\n', '</p><p>', html_body)
        html_body = f'<p>{html_body}</p>'
        html_body = html_body.replace('</p><p><h', '</p><h').replace('</h></p>', '</h>')
        
        html += html_body
        html += """
</body>
</html>
"""
        return html
    
    def generate_all(self):
        """Generate HTML for all documentation sources."""
        self.html_output_dir.mkdir(parents=True, exist_ok=True)
        
        generated_count = 0
        for doc_path in self.docs_source:
            source_file = self.workspace_root / doc_path
            
            if not source_file.exists():
                print(f"⚠️  Skipped (not found): {doc_path}")
                continue
            
            # Read markdown
            with open(source_file, 'r') as f:
                markdown_content = f.read()
            
            # Extract title
            title_match = re.search(r'^#\s+(.+?)$', markdown_content, re.MULTILINE)
            title = title_match.group(1) if title_match else doc_path
            
            # Generate HTML
            html_content = self.markdown_to_html(markdown_content, title)
            
            # Write HTML sister
            html_filename = source_file.stem + ".html"
            html_output_path = self.html_output_dir / html_filename
            
            with open(html_output_path, 'w') as f:
                f.write(html_content)
            
            generated_count += 1
            print(f"✅ {doc_path} → {html_output_path.relative_to(self.workspace_root)}")
        
        return generated_count
    
    def generate_index(self):
        """Generate an HTML index of all documentation."""
        index_html = """<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Assert.IQ Documentation Index</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
               line-height: 1.6; max-width: 900px; margin: 0 auto; padding: 20px; }
        h1 { color: #0366d6; border-bottom: 2px solid #0366d6; }
        .doc-list { list-style: none; padding: 0; }
        .doc-item { margin: 12px 0; padding: 12px; background: #f6f8fa; border-radius: 6px; }
        a { color: #0366d6; text-decoration: none; }
        a:hover { text-decoration: underline; }
        .meta { color: #666; font-size: 0.9em; }
    </style>
</head>
<body>
    <h1>Assert.IQ v1.7.0 Documentation</h1>
    <p>Searchable, styled HTML versions of Assert.IQ documentation for easier navigation.</p>
    <ul class="doc-list">
"""
        
        for doc_path in self.docs_source:
            source_file = self.workspace_root / doc_path
            if not source_file.exists():
                continue
            
            html_filename = source_file.stem + ".html"
            relative_path = Path("docs/html") / html_filename
            
            # Extract title
            with open(source_file, 'r') as f:
                content = f.read()
            title_match = re.search(r'^#\s+(.+?)$', content, re.MULTILINE)
            title = title_match.group(1) if title_match else doc_path
            
            index_html += f"""        <li class="doc-item">
            <a href="{relative_path}">{title}</a>
            <div class="meta">Source: {doc_path}</div>
        </li>
"""
        
        index_html += """    </ul>
</body>
</html>
"""
        
        index_path = self.html_output_dir / "index.html"
        with open(index_path, 'w') as f:
            f.write(index_html)
        
        print(f"✅ Documentation index: {index_path.relative_to(self.workspace_root)}")
        return index_path


if __name__ == "__main__":
    generator = DocumentationGenerator()
    
    print("=== Generating HTML Documentation Sisters ===")
    count = generator.generate_all()
    generator.generate_index()
    
    print(f"\n✅ Generated {count} HTML files")
    print("   Next: Search index generation")
