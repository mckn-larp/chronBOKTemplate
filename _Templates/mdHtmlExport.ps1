
<#
.SYNOPSIS
    Converts Markdown files in a directory to responsive HTML with basic sanitization.
.DESCRIPTION
    This script walks through a directory of Markdown files, converts them to HTML with Pandoc,
    adjusts internal links and image formats, and copies/resizes image assets as PNG.
.PARAMETER InputDir
    The input directory containing Markdown files.
.PARAMETER OutputDir
    The target directory where HTML files will be created.
.PARAMETER Title
    Optional title to use for pages without a heading.
.EXAMPLE
    .\mdHtmlExport.ps1 -InputDir ".\docs" -OutputDir ".\site" -Title "Project Docs"
#>

param (
    [Parameter(Mandatory=$true)][string]$InputDir,
    [Parameter(Mandatory=$true)][string]$OutputDir,
    [string]$Title = "Document"
)

function Sanitize-Markdown($content) {
    return $content -replace '^---$', '***'
}

function Fix-Links($content) {
    $content = $content -replace '\.md\)', '.html)'
    $content = $content -replace '\.(jpg|jpeg|webp|svg)\)', '.png)'
    return $content
}

function Get-FirstHeader($filePath) {
    $lines = Get-Content $filePath
    foreach ($line in $lines) {
        if ($line -match '^#{1,2} ') {
            return ($line -replace '^#+\s*', '')
        }
    }
    return $null
}

# Create the header HTML file
$headerFile = New-TemporaryFile
@"
<meta name='viewport' content='width=device-width, initial-scale=1'>
<style>
  body { max-width: 80%; margin: auto;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Oxygen, Ubuntu, sans-serif;
    line-height: 1.6; padding: 1em; box-sizing: border-box; }
  p { text-align: justify; }
  img { max-width: 100%; height: auto; }
  pre { overflow-x: auto; }
</style>
"@ | Set-Content $headerFile

# Ensure output directory
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

# Convert and copy images
Get-ChildItem -Recurse -Path $InputDir -Include *.png, *.jpg, *.jpeg, *.webp, *.svg | ForEach-Object {
    $relPath = $_.FullName.Substring($InputDir.Length).TrimStart('\')
    $targetPath = Join-Path $OutputDir ($relPath -replace '\.[^\.]+$', '.png')
    $targetDir = Split-Path $targetPath -Parent
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }
    Write-Host "  + Converting $relPath → $($targetPath.Substring($OutputDir.Length + 1))"
    magick $_.FullName -resize 500x500 $targetPath
}

# Convert Markdown files
Get-ChildItem -Recurse -Path $InputDir -Filter *.md | ForEach-Object {
    $relPath = $_.FullName.Substring($InputDir.Length).TrimStart('\')
    $relDir = Split-Path $relPath -Parent
    $baseName = $_.BaseName
    $outFile = if ($_.Name -imatch '^readme\.md$') {
        if ($relDir -eq '') { Join-Path $OutputDir 'index.html' }
        else { Join-Path $OutputDir $relDir 'readme.html' }
    } else {
        Join-Path $OutputDir $relDir "$baseName.html"
    }

    $outDir = Split-Path $outFile -Parent
    if (-not (Test-Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }

    Write-Host "  Converting: $($_.FullName) → $outFile"
    $mdContent = Get-Content $_.FullName -Raw
    $mdContent = Sanitize-Markdown $mdContent
    $mdContent = Fix-Links $mdContent
    $pageTitle = Get-FirstHeader $_.FullName
    if (-not $pageTitle) { $pageTitle = $Title }

    $tempFile = New-TemporaryFile
    $mdContent | Set-Content $tempFile

    pandoc $tempFile -f markdown -t html5 -s `
        -M "title=$pageTitle" `
        --include-in-header=$headerFile `
        -o $outFile

    Remove-Item $tempFile -Force
}

Remove-Item $headerFile -Force
Write-Host "HTML export complete."
