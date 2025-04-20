#!/bin/bash

# Usage: mdHtmlExporter.sh <inputDir> <outputDir> [--title "Your Title Here"]

INPUT_DIR=""
OUTPUT_DIR=""
DOC_TITLE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --title)
            shift
            DOC_TITLE="$1"
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            if [[ -z "$INPUT_DIR" ]]; then
                INPUT_DIR="$1"
            elif [[ -z "$OUTPUT_DIR" ]]; then
                OUTPUT_DIR="$1"
            else
                echo "Too many positional arguments."
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$INPUT_DIR" || -z "$OUTPUT_DIR" ]]; then
    echo "Usage: $0 <input directory> <output directory> [--title \"Title\"]"
    exit 1
fi

echo "Input Directory: $INPUT_DIR"
echo "Output Directory: $OUTPUT_DIR"

# Extracts the first header (H1 or H2) to use as the page title
extract_title() {
    grep -m 1 -E '^#{1,2} ' "$1" | sed 's/^#* //'
}

# Converts .md → .html and common image formats → .png
fix_links() {
    sed -E \
        -e 's/\.md\)/.html)/g' \
        -e 's/\.(jpg|jpeg|webp|svg)\)/.png)/Ig'
}

# Fixes the --- to *** for pandoc compatibility
sanitize_md() {
    sed -E 's/^---$/***/'
}

# Create a temporary header file with responsive CSS
HEADER_FILE="$(mktemp)"
cat <<'EOF' > "$HEADER_FILE"
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  body { max-width: 80%; margin: auto;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Oxygen, Ubuntu, sans-serif;
    line-height: 1.6; padding: 1em; box-sizing: border-box; }
  p { text-align: justify; }
  img { max-width: 100%; height: auto; }
  pre { overflow-x: auto; }
</style>
EOF

export -f fix_links

# Step 1: Convert and copy image files to OUTPUT_DIR with PNG format, keeping structure
echo "Converting and copying images to: $OUTPUT_DIR"
find "$INPUT_DIR" -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" -o -iname "*.svg" \) | while read -r img; do
    rel_path="${img#$INPUT_DIR/}"
    target_path="$OUTPUT_DIR/${rel_path%.*}.png"
    target_dir="$(dirname "$target_path")"
    mkdir -p "$target_dir"

    echo "  + Converting $rel_path → ${target_path#$OUTPUT_DIR/}"
    convert "$img" -resize '500x500>' "$target_path" 2>/dev/null
done

# Step 2: Convert Markdown files
find "$INPUT_DIR" \( -type d -name '.*' -o -name '_*' \) -prune -false -o -type f -iname "*.md" | while read -r md_file; do
    rel_path="${md_file#$INPUT_DIR/}"
    rel_dir="$(dirname "$rel_path")"
    base_name="$(basename "$md_file")"

    # Set output path
    mkdir -p "$OUTPUT_DIR/$rel_dir"
    if [[ "$base_name" =~ [Rr][Ee][Aa][Dd][Mm][Ee]\.md ]]; then
        if [[ "$rel_dir" == "." ]]; then
            # Root-level README becomes index.html
            out_file="$OUTPUT_DIR/index.html"
        else
            # Other README files become readme.html
            out_file="$OUTPUT_DIR/$rel_dir/readme.html"
        fi
    else
        out_file="$OUTPUT_DIR/$rel_dir/${base_name%.md}.html"
    fi

    echo "  Converting: $md_file → $out_file"

    PAGE_TITLE="$(extract_title "$md_file")"
    [ -z "$PAGE_TITLE" ] && PAGE_TITLE="$DOC_TITLE"

    cat "$md_file" | sanitize_md | fix_links | pandoc -f markdown -t html5 -s \
        -M title="$PAGE_TITLE" --include-in-header="$HEADER_FILE" -o "$out_file"
done

echo "HTML export complete."
rm -f "$HEADER_FILE"