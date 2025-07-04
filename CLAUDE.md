# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Custom Linux Install Tool that includes a comprehensive font archival system (`font.sh`). The project is structured as a Python package but currently contains primarily shell scripts for font management operations.

## Key Components

### font.sh - Unified Font Archival System
- **Purpose**: Downloads, organizes, and manages fonts from GitHub repositories
- **Key Features**:
  - Downloads fonts from GitHub repos (with Git LFS support)
  - Organizes fonts by family and type into `/usr/share/fonts`
  - Detects and properly handles Nerd Fonts
  - Supports multiple archive formats (zip, 7z, tar.gz, rar)
  - Cross-platform package management (apt, dnf, pacman, etc.)
  - Font deduplication and cache management

### Architecture
- **Font Organization**: Fonts are organized in `/usr/share/fonts/{type}/{family}/` structure
- **Font Detection**: Uses `fc-query` (fontconfig) for font metadata extraction
- **Nerd Font Detection**: Identifies Nerd Fonts via Private Use Area glyphs (E000-F8FF range)
- **Package Management**: Auto-detects Linux distribution and uses appropriate package manager

## Development Commands

### Running the Font Tool
```bash
# Show help
./font.sh --help

# Download fonts from GitHub
./font.sh download-github -r https://github.com/user/Font-Storage

# Organize fonts (requires root)
sudo ./font.sh organize

# Full process (download, extract, organize)
sudo ./font.sh full-process -r https://github.com/user/Font-Storage
```

### Python Package Management
```bash
# Install dependencies (if any are added)
pip install -e .

# The project uses pyproject.toml for package configuration
```

## Important Implementation Details

### Font Processing Pipeline
1. **Collection**: Gathers fonts from current directory, extracted archives, and GitHub repos
2. **Analysis**: Uses `fc-query` to extract font family names and metadata
3. **Sanitization**: Normalizes font family names (lowercase, alphanumeric only)
4. **Organization**: Places fonts in structured directories by type and family
5. **Cache Update**: Refreshes system font cache with `fc-cache`

### Dependency Management
- **Critical**: git, curl, fontconfig, coreutils, findutils
- **Optional**: 7z, unzip, unrar, python3, git-lfs
- Auto-installs missing dependencies when run with sudo

### Security Considerations
- Requires root privileges for system font installation
- Validates GitHub URLs before cloning
- Sanitizes font family names to prevent path traversal

## Common Development Patterns

### Adding New Archive Support
Extend the `extract_archives()` function case statement with new file extensions and extraction commands.

### Modifying Font Organization
Update the `organize_fonts()` function to change directory structure or naming conventions.

### Cross-Platform Support
Add new package managers to `get_package_manager()` and update `install_package()` accordingly.