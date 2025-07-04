#!/bin/bash

# Unified Font Archival System
# Combines font organization, deduplication, and GitHub repository management
# 1. Downloads fonts from GitHub repositories
# 2. Scans local Windows fonts (if on Windows/WSL)
# 3. Organizes fonts into proper directory structure
# 4. Deduplicates fonts across the system
# 5. Optionally uploads organized fonts to GitHub

set -euo pipefail

# Font type mappings
declare -A font_type_map=(
     ["ttf"]="truetype"
     ["otf"]="opentype"
     ["woff"]="webfonts"
     ["woff2"]="webfonts"
     ["pfb"]="type1"
     ["pfa"]="type1"
     ["pfm"]="type1"
)

# Cleanup function
cleanup() {
    rm -rf "$TEMP_PROCESSING_DIR"
    if [[ -d "$TEMP_EXTRACT_DIR" ]]; then
        print_color "$YELLOW" "Cleaning up temporary extraction directory..."
        rm -rf "$TEMP_EXTRACT_DIR"
  fi
}

# Function to print colored output
print_color() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

# Function to show help
show_help() {
    cat << EOF
Unified Font Archival System

USAGE: $0 [OPTIONS] [COMMAND]

COMMANDS:
  download-github    Download fonts from GitHub repositories
  scan-windows      Scan Windows fonts (WSL/Windows only)
  organize          Organize fonts from current directory
  deduplicate       Find and remove duplicate fonts
  upload-github     Upload organized fonts to GitHub
  full-process      Run complete process (download -> organize -> deduplicate)

OPTIONS:
  -h, --help        Show this help message
  -r, --repo URL    GitHub repository URL to download from
  -t, --token FILE  GitHub token file path
  -o, --output DIR  Output directory for organized fonts
  -c, --config FILE Configuration file path
  -v, --verbose     Enable verbose output
  -n, --dry-run     Show what would be done without doing it
  --reset          Reset font directories to initial state
  --backup         Create backup of current font organization

EXAMPLES:
  $0 download-github -r https://github.com/user/Font-Storage
  $0 organize /path/to/fonts
  $0 full-process -r https://github.com/user/Font-Storage
  $0 deduplicate

DEPENDENCIES:
  Required: git, curl, fontconfig, coreutils, findutils
  Optional: 7z, unzip, unrar, python3 (for advanced features)

EOF
}

# Function to detect Linux distribution
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "$ID"
  elif   [[ -f /etc/debian_version ]]; then
        echo "debian"
  elif   [[ -f /etc/redhat-release ]]; then
        echo "rhel"
  elif   [[ -f /etc/arch-release ]]; then
        echo "arch"
  elif   [[ -f /etc/alpine-release ]]; then
        echo "alpine"
  else
        echo "unknown"
  fi
}

# Function to get package manager
get_package_manager() {
    local distro
    distro=$(detect_distro)
    case "$distro" in
        ubuntu* | debian* | pop* | elementary* | mint*)
            echo "apt"
            ;;
        fedora* | rhel* | centos* | rocky* | alma*)
            echo "dnf"
            ;;
        opensuse* | sles*)
            echo "zypper"
            ;;
        arch* | manjaro* | endeavouros*)
            echo "pacman"
            ;;
        alpine*)
            echo "apk"
            ;;
        *)
            echo "unknown"
            ;;
  esac
}

# Function to update package lists
update_package_lists() {
    local pkg_manager
    pkg_manager=$(get_package_manager)

    print_color "$BLUE" "Updating package lists..."

    case "$pkg_manager" in
        "apt")
            apt update > /dev/null 2>&1 && return 0 || return 1
            ;;
        "dnf")
            dnf check-update > /dev/null 2>&1 && return 0 || return 1
            ;;
        "zypper")
            zypper refresh > /dev/null 2>&1 && return 0 || return 1
            ;;
        "pacman")
            pacman -Sy > /dev/null 2>&1 && return 0 || return 1
            ;;
        "apk")
            apk update > /dev/null 2>&1 && return 0 || return 1
            ;;
        *)
            return 1
            ;;
  esac
}

# Function to install a single package
install_package() {
    local package="$1"
    local pkg_manager
    pkg_manager=$(get_package_manager)

    print_color "$CYAN" "Installing $package..."

    case "$pkg_manager" in
        "apt")
            apt install -y "$package" > /dev/null 2>&1 && return 0 || return 1
            ;;
        "dnf")
            dnf install -y "$package" > /dev/null 2>&1 && return 0 || return 1
            ;;
        "zypper")
            zypper install -y "$package" > /dev/null 2>&1 && return 0 || return 1
            ;;
        "pacman")
            pacman -S --noconfirm "$package" > /dev/null 2>&1 && return 0 || return 1
            ;;
        "apk")
            apk add "$package" > /dev/null 2>&1 && return 0 || return 1
            ;;
        *)
            return 1
            ;;
  esac
}

# Function to map commands to packages
get_package_name() {
    local command="$1"
    local distro
    distro=$(detect_distro)

    case "$command" in
        "git" | "curl" | "unzip")
            echo "$command"
            ;;
        "md5sum" | "stat" | "find")
            echo "coreutils"
            ;;
        "fc-query" | "fc-cache")
            echo "fontconfig"
            ;;
        "7z")
            case "$distro" in
                ubuntu* | debian* | pop* | elementary* | mint*)
                    echo "p7zip-full"
                    ;;
                *)
                    echo "p7zip"
                    ;;
      esac
            ;;
        "unrar")
            echo "unrar"
            ;;
        "python3")
            case "$distro" in
                arch* | manjaro* | endeavouros*)
                    echo "python"
                    ;;
                *)
                    echo "python3"
                    ;;
      esac
            ;;
        "git-lfs")
            echo "git-lfs"
            ;;
        *)
            echo "$command"
            ;;
  esac
}

# Function to check dependencies
check_dependencies() {
    print_color "$BLUE" "Checking dependencies..."

    local missing_critical=()
    local missing_optional=()
    local cmd
    local dep

    # Critical dependencies
    local critical_commands=("git" "curl" "md5sum" "stat" "find" "fc-query" "fc-cache")

    for cmd in "${critical_commands[@]}"; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            missing_critical+=("$cmd")
    fi
  done

    # Optional dependencies
    local optional_commands=("7z" "unzip" "unrar" "python3" "git-lfs")

    for cmd in "${optional_commands[@]}"; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            missing_optional+=("$cmd")
    fi
  done

    # Handle missing critical dependencies
    if [[ ${#missing_critical[@]} -gt 0 ]]; then
        print_color "$RED" "❌ Missing critical dependencies:"
        for dep in "${missing_critical[@]}"; do
            print_color "$RED" "   - $dep"
    done

        # Get packages to install
        local packages_to_install=()
        for cmd in "${missing_critical[@]}"; do
            local pkg
            pkg=$(get_package_name "$cmd")
            if [[ ! " ${packages_to_install[*]} " =~ \ $pkg\  ]]; then
                packages_to_install+=("$pkg")
      fi
    done

        print_color "$YELLOW" "Required packages: ${packages_to_install[*]}"

        # Offer to install if running as root
        if [[ $EUID -eq 0 ]]; then
            print_color "$CYAN" "Install missing packages? [y/N]:"
            read -p "Choice: " -n 1 -r
            echo

            if [[ $REPLY =~ ^[Yy]$ ]]; then
                update_package_lists
                for pkg in "${packages_to_install[@]}"; do
                    if install_package "$pkg"; then
                        print_color "$GREEN" "  ✅ $pkg installed"
          else
                        print_color "$RED" "  ❌ Failed to install $pkg"
          fi
        done
      fi
    else
            print_color "$YELLOW" "Run with sudo to enable automatic installation"
    fi

        # Re-check critical dependencies
        local still_missing=false
        for cmd in "${critical_commands[@]}"; do
            if ! command -v "$cmd" > /dev/null 2>&1; then
                still_missing=true
                break
      fi
    done

        if [[ $still_missing == "true"   ]]; then
            print_color "$RED" "Cannot continue without critical dependencies"
            return 1
    fi
  fi

    # Handle optional dependencies
    if [[ ${#missing_optional[@]} -gt 0 ]]; then
        print_color "$YELLOW" "⚠️  Missing optional dependencies:"
        for dep in "${missing_optional[@]}"; do
            print_color "$YELLOW" "   - $dep"
    done
  fi

    print_color "$GREEN" "✅ Dependency check complete"
    return 0
}

# Function to check if running on Windows/WSL
is_windows_or_wsl() {
    if [[ -n ${WSL_DISTRO_NAME:-}   ]] || [[ "$(uname -r)" == *microsoft* ]] || [[ "$(uname -r)" == *WSL* ]]; then
        return 0
  fi
    return 1
}

# Function to validate GitHub URL
validate_github_url() {
    local url="$1"
    if [[ "$url" =~ ^https://github\.com/[^/]+/[^/]+/?$ ]]; then
        return 0
  elif   [[ "$url" =~ ^[^/]+/[^/]+$ ]]; then
        return 0
  else
        return 1
  fi
}

# Function to normalize GitHub URL
normalize_github_url() {
    local url="$1"
    if [[ "$url" =~ ^https://github\.com/(.+)$ ]]; then
        echo "https://github.com/${BASH_REMATCH[1]}"
  elif   [[ "$url" =~ ^[^/]+/[^/]+$ ]]; then
        echo "https://github.com/$url"
  else
        echo "$url"
  fi
}

# Function to download fonts from GitHub
download_github_fonts() {
    local repo_url="$1"
    local clone_dir="${2:-$GITHUB_CLONE_DIR}"

    print_color "$BLUE" "Downloading fonts from GitHub repository..."
    print_color "$CYAN" "Repository: $repo_url"
    print_color "$CYAN" "Clone directory: $clone_dir"

    # Validate URL
    if ! validate_github_url "$repo_url"; then
        print_color "$RED" "Error: Invalid GitHub repository URL: $repo_url"
        return 1
  fi

    # Normalize URL
    repo_url=$(normalize_github_url "$repo_url")

    # Remove existing clone directory if it exists
    if [[ -d "$clone_dir" ]]; then
        print_color "$YELLOW" "Removing existing clone directory..."
        rm -rf "$clone_dir"
  fi

    # Clone repository
    print_color "$CYAN" "Cloning repository..."
    if ! git clone "$repo_url" "$clone_dir"; then
        print_color "$RED" "Error: Failed to clone repository"
        return 1
  fi

    # Check if Git LFS is needed
    if [[ -f "$clone_dir/.gitattributes" ]] && grep -q "lfs" "$clone_dir/.gitattributes"; then
        print_color "$CYAN" "Git LFS detected, pulling LFS files..."
        if command -v git-lfs > /dev/null 2>&1; then
            cd "$clone_dir"
            git lfs pull || true
            cd - > /dev/null
    else
            print_color "$YELLOW" "Warning: Git LFS not installed, some files may not be downloaded"
    fi
  fi

    # Count downloaded fonts
    local font_count=0
    while IFS= read -r -d '' font_file; do
        font_count=$((font_count + 1))
  done   < <(find "$clone_dir" -type f \( -iname "*.ttf" -o -iname "*.otf" -o -iname "*.woff" -o -iname "*.woff2" -o -iname "*.pfb" -o -iname "*.pfa" -o -iname "*.pfm" \) -print0 2> /dev/null || true)

    print_color "$GREEN" "Downloaded $font_count font files from GitHub"
    return 0
}

# Function to detect if font is a Nerd Font
is_nerd_font() {
    local font_file="$1"
    local has_nerd_glyphs=false

    # Method 1: Use fc-query to check for Private Use Area glyphs
    if command -v fc-query > /dev/null 2>&1; then
        local charset
        charset=$(fc-query -f "%{charset}" "$font_file" 2> /dev/null || true)
        if [[ -n "$charset" ]]; then
            # Look for characteristic Nerd Font ranges (E000-F8FF)
            if echo "$charset" | grep -qE "(e[0-9a-f]{3}|f[0-7][0-9a-f]{2})"; then
                has_nerd_glyphs=true
      fi
    fi
  fi

    # Method 2: Check filename and family name for Nerd Font indicators
    if [[ "$has_nerd_glyphs" == "false" ]]; then
        local filename
        filename=$(basename "$font_file")
        local family_from_file=""

        if command -v fc-query > /dev/null 2>&1; then
            family_from_file=$(fc-query -f "%{family[0]}" "$font_file" 2> /dev/null || true)
    fi

        if [[ $filename =~ [Nn]erd|NF|[Pp]owerline   ]] \
                                                        || [[ $family_from_file =~ [Nn]erd|NF|[Pp]owerline ]]; then
            has_nerd_glyphs=true
    fi
  fi

    echo "$has_nerd_glyphs"
}

# Function to sanitize font family name
sanitize_font_name() {
    local name="$1"

    # Convert to lowercase
    name=$(echo "$name" | tr '[:upper:]' '[:lower:]')

    # Remove spaces and common separators
    name=$(echo "$name" | tr -d '[:space:]' | sed 's/[-_.]//g')

    # Keep only ASCII alphanumeric characters
    name=${name//[^a-z0-9]/}

    # Remove repetitive patterns
    local prev_name=""
    while [[ $name != "$prev_name"   ]]; do
        prev_name="$name"
        if [[ $name =~ ^(.+)\1+$   ]]; then
            name="${BASH_REMATCH[1]}"
    fi
  done

    # Ensure we have something
    if [[ -z $name   ]]; then
        name="unknown"
  fi

    # Limit length
    if [[ ${#name} -gt 50 ]]; then
        name="${name:0:50}"
  fi

    echo "$name"
}

# Function to get font family name
get_font_family() {
    local font_file="$1"
    local family=""
    local raw_family=""
    local is_nerd
    is_nerd=$(is_nerd_font "$font_file")

    # Method 1: fc-query
    if command -v fc-query > /dev/null 2>&1; then
        raw_family=$(fc-query -f "%{family[0]}" "$font_file" 2> /dev/null || true)
        if [[ -n $raw_family && $raw_family != "Unknown Family"     ]]; then
            raw_family=$(echo "$raw_family" | sed -E 's/\s*(Nerd Font|NF|Powerline)\s*//gi' | sed -E 's/\s+/ /g' | sed 's/^ *//;s/ *$//')
            family=$(sanitize_font_name "$raw_family")
    fi
  fi

    # Method 2: Fallback to filename parsing
    if [[ -z $family   ]]; then
        local basename
        basename=$(basename "$font_file")
        basename=${basename%.*}
        basename=$(echo "$basename" | sed -E 's/(Nerd|NF|Powerline)//gi')

        local style_keywords="regular|normal|bold|italic|light|medium|heavy|black|thin|condensed|extended|oblique|roman"
        raw_family=$(echo "$basename" | sed -E "s/[-_[:space:]]*($style_keywords).*//i")

        if [[ "$raw_family" == "$basename" ]]; then
            raw_family=$(echo "$basename" | sed -E 's/[-_[:space:]].*//')
    fi

        if [[ -z "$raw_family" ]]; then
            raw_family="$basename"
    fi

        family=$(sanitize_font_name "$raw_family")
  fi

    # Add NF suffix for Nerd Fonts
    if [[ "$is_nerd" == "true" ]]; then
        family=$(echo "$family" | sed -E 's/(nf|NF)+$//i')
        if [[ ! "$family" =~ (nf|NF)$ ]]; then
            family="${family}NF"
    fi
  fi

    # Final fallback
    if [[ -z "$family" ]] || [[ "$family" == "NF" ]] || [[ "$family" == "nf" ]]; then
        if [[ "$is_nerd" == "true" ]]; then
            family="unknownNF"
    else
            family="unknown"
    fi
  fi

    echo "$family"
}

# Function to get font type
get_font_type() {
    local font_file="$1"
    local ext="${font_file##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

    local font_type="${font_type_map[$ext]:-unknown}"
    echo "$font_type"
}

# Function to extract archives
extract_archives() {
    print_color "$BLUE" "Extracting archives in current directory..."

    local archives_found=false
    local archive
    mkdir -p "$TEMP_EXTRACT_DIR"

    while IFS= read -r -d '' archive; do
        archives_found=true
        print_color "$CYAN" "Extracting: $(basename "$archive")"

        local archive_name
        archive_name=$(basename "$archive")
        local extract_subdir="$TEMP_EXTRACT_DIR/${archive_name%.*}"
        mkdir -p "$extract_subdir"

        case "${archive,,}" in
            *.zip)
                if command -v unzip > /dev/null 2>&1; then
                    unzip -q "$archive" -d "$extract_subdir" || print_color "$YELLOW" "Warning: Failed to extract $archive"
        else
                    print_color "$YELLOW" "Warning: unzip not available, skipping $archive"
        fi
                ;;
            *.7z)
                if command -v 7z > /dev/null 2>&1; then
                    7z x "$archive" -o"$extract_subdir" -y > /dev/null || print_color "$YELLOW" "Warning: Failed to extract $archive"
        else
                    print_color "$YELLOW" "Warning: 7z not available, skipping $archive"
        fi
                ;;
            *.tar.gz | *.tgz)
                tar -xzf "$archive" -C "$extract_subdir" || print_color "$YELLOW" "Warning: Failed to extract $archive"
                ;;
            *.tar.bz2 | *.tbz2)
                tar -xjf "$archive" -C "$extract_subdir" || print_color "$YELLOW" "Warning: Failed to extract $archive"
                ;;
            *.tar.xz)
                tar -xJf "$archive" -C "$extract_subdir" || print_color "$YELLOW" "Warning: Failed to extract $archive"
                ;;
            *.rar)
                if command -v unrar > /dev/null 2>&1; then
                    unrar x "$archive" "$extract_subdir/" || print_color "$YELLOW" "Warning: Failed to extract $archive"
        else
                    print_color "$YELLOW" "Warning: unrar not available, skipping $archive"
        fi
                ;;
            *)
                print_color "$YELLOW" "Warning: Unknown archive format: $archive"
                ;;
    esac
  done   < <(find "$CURRENT_DIR" -maxdepth 1 -type f \( -iname "*.zip" -o -iname "*.7z" -o -iname "*.tar.gz" -o -iname "*.tgz" -o -iname "*.tar.bz2" -o -iname "*.tbz2" -o -iname "*.tar.xz" -o -iname "*.rar" \) -print0 2> /dev/null || true)

    if [[ "$archives_found" == "false" ]]; then
        print_color "$GREEN" "No archives found in current directory."
  fi
}

# Function to collect all font files
collect_fonts() {
    print_color "$BLUE" "Collecting font files..."

    local fonts_list="$TEMP_PROCESSING_DIR/fonts_to_process.txt"
    true > "$fonts_list"

    # Collect fonts from current directory
    find "$CURRENT_DIR" -maxdepth 1 -type f \( -iname "*.ttf" -o -iname "*.otf" -o -iname "*.woff" -o -iname "*.woff2" -o -iname "*.pfb" -o -iname "*.pfa" -o -iname "*.pfm" \) -print >> "$fonts_list" 2> /dev/null || true

    # Collect fonts from extracted archives
    if [[ -d "$TEMP_EXTRACT_DIR" ]]; then
        find "$TEMP_EXTRACT_DIR" -type f \( -iname "*.ttf" -o -iname "*.otf" -o -iname "*.woff" -o -iname "*.woff2" -o -iname "*.pfb" -o -iname "*.pfa" -o -iname "*.pfm" \) -print >> "$fonts_list" 2> /dev/null || true
  fi

    # Collect fonts from GitHub clone directory
    if [[ -d $GITHUB_CLONE_DIR   ]]; then
        find "$GITHUB_CLONE_DIR" -type f \( -iname "*.ttf" -o -iname "*.otf" -o -iname "*.woff" -o -iname "*.woff2" -o -iname "*.pfb" -o -iname "*.pfa" -o -iname "*.pfm" \) -print >> "$fonts_list" 2> /dev/null || true
  fi

    local font_count=0
    if [[ -f $fonts_list   ]]; then
        font_count=$(wc -l < "$fonts_list" 2> /dev/null || echo "0")
  fi

    print_color "$GREEN" "Found $font_count font files to process."
    echo "$fonts_list"
}

# Function to organize fonts (requires root)
organize_fonts() {
    local fonts_list="$1"
    print_color "$BLUE" "Organizing fonts into proper directory structure..."

    if [[ $EUID -ne 0 ]]; then
        print_color "$RED" "This operation requires root privileges to organize system fonts."
        print_color "$YELLOW" "Run with: sudo $0 organize"
        return 1
  fi

    if [[ ! -f $fonts_list   ]]; then
        print_color "$RED" "Error: Font list file not found: $fonts_list"
        return 1
  fi

    local organized_count=0
    local total_fonts
    total_fonts=$(wc -l < "$fonts_list" 2> /dev/null || echo "0")

    if [[ $total_fonts -eq 0   ]]; then
        print_color "$YELLOW" "No fonts to organize."
        return 0
  fi

    print_color "$GREEN" "Processing $total_fonts font files..."

    while IFS= read -r font_file; do
        [[ -z $font_file   ]] && continue
        [[ ! -f $font_file   ]] && continue

        local family
        family=$(get_font_family "$font_file")
        local font_type
        font_type=$(get_font_type "$font_file")
        local is_nerd
        is_nerd=$(is_nerd_font "$font_file")

        # Create target directory
        local target_dir="$FONTS_BASE_DIR/$font_type/$family"
        local target_file
        target_file="$target_dir/$(basename "$font_file")"

        print_color "$CYAN" "Processing: $(basename "$font_file")"
        print_color "$CYAN" "  Font family: '$family'"
        if [[ $is_nerd == "true"   ]]; then
            print_color "$YELLOW" "  🎯 Nerd Font detected!"
    fi
        print_color "$CYAN" "  Target: $font_type/$family/"

        # Create directory if it doesn't exist
        if ! mkdir -p "$target_dir"; then
            print_color "$RED" "  Failed to create directory: $target_dir"
            continue
    fi

        # Check if file already exists
        if [[ -f $target_file   ]]; then
            if cmp -s "$font_file" "$target_file"; then
                print_color "$YELLOW" "  Already exists (identical): $target_file"
      else
                print_color "$YELLOW" "  Already exists (different): $target_file"
      fi
    else
            # Copy font to target location
            if cp "$font_file" "$target_file"; then
                print_color "$GREEN" "  Organized: $target_file"
                organized_count=$((organized_count + 1))
      else
                print_color "$RED" "  Failed to copy: $font_file"
      fi
    fi
  done   < "$fonts_list"

    print_color "$GREEN" "Organized $organized_count font files."
}

# Function to update font cache
update_font_cache() {
    print_color "$BLUE" "Updating font cache..."

    if command -v fc-cache > /dev/null 2>&1; then
        print_color "$CYAN" "Updating font cache (this may take a moment)..."
        if fc-cache -f > /dev/null 2>&1; then
            print_color "$GREEN" "Font cache updated successfully."
    else
            print_color "$YELLOW" "Font cache update completed with warnings."
    fi
  else
        print_color "$YELLOW" "fc-cache not available. Font cache not updated."
  fi
}

# Function to run full process
run_full_process() {
    local repo_url="$1"
    local token_file="$2"  # TODO: Implement GitHub token authentication - currently unused

    print_color "$BLUE" "Running full font archival process..."

    # Step 1: Download from GitHub if URL provided
    if [[ -n $repo_url   ]]; then
        if ! download_github_fonts "$repo_url"; then
            print_color "$RED" "Error: Failed to download fonts from GitHub"
            return 1
    fi
  fi

    # Step 2: Extract archives
    extract_archives

    # Step 3: Collect fonts
    local fonts_list
    fonts_list=$(collect_fonts)

    # Step 4: Organize fonts (requires root)
    if [[ $EUID -eq 0 ]]; then
        organize_fonts "$fonts_list"
  else
        print_color "$YELLOW" "Skipping organization (requires root privileges)"
        print_color "$YELLOW" "Run with sudo to organize fonts into system directories"
  fi

    # Step 5: Update font cache
    update_font_cache

    print_color "$GREEN" "Full font archival process completed!"
}

# Main function
main() {
    local command=""
    local repo_url=""
    local token_file=""
    local output_dir=""
    local verbose=false
    local dry_run=false

    # TODO: Implement scan_windows() function to use this array
    default_windows_fonts=(
    "arial" "calibri" "cambria" "candara" "comic sans ms" "consolas" "constantia"
    "corbel" "courier new" "ebrima" "franklin gothic" "gabriola" "gadugi"
    "georgia" "impact" "javanese text" "leelawadee ui" "lucida console"
    "lucida sans unicode" "malgun gothic" "microsoft sans serif" "mingliu"
    "ms gothic" "ms pgothic" "ms ui gothic" "mv boli" "myanmar text" "nirmala ui"
    "palatino linotype" "segoe mdl2 assets" "segoe print" "segoe script"
    "segoe ui" "simsun" "sitka" "sylfaen" "symbol" "tahoma" "times new roman"
    "trebuchet ms" "verdana" "webdings" "wingdings" "yu gothic"
)
    # Colors for output
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    WHITE='\033[1;37m'
    NC='\033[0m' # No Color

    # Configuration
    FONTS_BASE_DIR="/usr/share/fonts"
    CURRENT_DIR="$(pwd)"
    TEMP_EXTRACT_DIR="$CURRENT_DIR/.font_temp_extract"
    TEMP_PROCESSING_DIR=$(mktemp -d)
    GITHUB_CLONE_DIR="$CURRENT_DIR/.github_fonts"
    CONFIG_FILE="$HOME/.font_archiver_config"

  # Run the main function if a script is executed directly
  if [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
    # Show a welcome message
    exit 0
  else
    show_welcome
  fi
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h | --help)
                show_help
                exit 0
                ;;
            -r | --repo)
                repo_url="$2"
                shift 2
                ;;
            -t | --token)
                token_file="$2"
                shift 2
                ;;
            -o | --output)
                output_dir="$2"
                shift 2
                ;;
            -v | --verbose)
                verbose=true
                shift
                ;;
            -n | --dry-run)
                dry_run=true
                shift
                ;;
            --reset)
                command="reset"
                shift
                ;;
            --backup)
                command="backup"
                shift
                ;;
            download-github | scan-windows | organize | deduplicate | upload-github | full-process)
                command="$1"
                shift
                ;;
            *)
                # Treat unknown arguments as potential directory paths
                if [[ -d "$1" ]]; then
                    CURRENT_DIR="$1"
                    shift
        else
                    print_color "$RED" "Unknown option: $1"
                    show_help
                    exit 1
        fi
                ;;
    esac
  done

    # Set defaults
    token_file="${token_file:-$HOME/.github_token}"
    output_dir="${output_dir:-$CURRENT_DIR/organized_fonts}"

    # Check dependencies first
    print_color "$BLUE" "🔍 Checking system dependencies..."
    if ! check_dependencies; then
        print_color "$RED" "❌ Critical dependencies missing. Cannot continue."
        print_color "$YELLOW" "💡 Tip: Run with sudo to enable automatic installation"
        exit 1
  fi

    # Execute command
    case "$command" in
        "download-github")
            if [[ -z "$repo_url" ]]; then
                print_color "$RED" "Error: Repository URL required for download-github command"
                print_color "$YELLOW" "Usage: $0 download-github -r <repo_url>"
                exit 1
      fi
            download_github_fonts "$repo_url"
            ;;
        "organize")
            extract_archives
            fonts_list=$(collect_fonts)
            organize_fonts "$fonts_list"
            update_font_cache
            ;;
        "full-process")
            run_full_process "$repo_url" "$token_file"
            ;;
        "")
            # No command specified, show help
            show_help
            ;;
        *)
            print_color "$RED" "Unknown command: $command"
            show_help
            exit 1
            ;;
  esac
}

# Function to display welcome message
show_welcome() {
    print_color "$BLUE" "╔════════════════════════════════════════════════════════════════╗"
    print_color "$BLUE" "║                 Unified Font Archival System                   ║"
    print_color "$BLUE" "║                                                                ║"
    print_color "$BLUE" "║  🎯 Download fonts from GitHub repositories                    ║"
    print_color "$BLUE" "║  📁 Organize fonts by family and type                          ║"
    print_color "$BLUE" "║  🔍 Find and remove duplicate fonts                            ║"
    print_color "$BLUE" "║  🚀 Upload organized collections to GitHub                     ║"
    print_color "$BLUE" "║  🖥️  Support for Windows fonts via WSL                         ║"
    print_color "$BLUE" "╚════════════════════════════════════════════════════════════════╝"
    echo
}

main "$@"