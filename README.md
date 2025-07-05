# Font Automation Tool

A comprehensive font archival system that downloads, organizes, and manages fonts from GitHub repositories.

## Features

- **GitHub Font Downloads**: Clone font repositories with Git LFS support
- **Smart Font Organization**: Automatically categorizes fonts by type and family
- **Nerd Font Detection**: Identifies and properly handles Nerd Fonts
- **Multi-format Support**: Handles TTF, OTF, WOFF, WOFF2, Type1 fonts
- **Archive Extraction**: Supports ZIP, 7Z, TAR.GZ, RAR archives
- **Cross-platform**: Works on major Linux distributions
- **Dependency Management**: Auto-installs required packages

## Installation

1. Clone the repository:
```bash
git clone https://github.com/tkirkland/Font_Automation_Tool.git
cd Font_Automation_Tool
```

2. Make the script executable:
```bash
chmod +x fat.sh
```

## Usage

### Download fonts from GitHub
```bash
./fat.sh download-github -r https://github.com/user/Font-Repository
```

### Organize fonts (requires root)
```bash
sudo ./fat.sh organize
```

### Full process (download, extract, organize)
```bash
sudo ./fat.sh full-process -r https://github.com/user/Font-Repository
```

### Extract archives in current directory
```bash
./fat.sh extract
```

### Show help
```bash
./fat.sh --help
```

## Font Organization

Fonts are organized in `/usr/share/fonts/` with the following structure:
```
/usr/share/fonts/
├── truetype/
│   ├── font-family-1/
│   └── font-family-2/
├── opentype/
│   ├── font-family-3/
│   └── font-family-4/
└── webfonts/
    ├── font-family-5/
    └── font-family-6/
```

## Dependencies

### Required
- git
- curl  
- fontconfig (fc-query, fc-cache)
- coreutils
- findutils

### Optional
- 7z (for 7Z archives)
- unzip (for ZIP archives)
- unrar (for RAR archives)
- python3
- git-lfs (for Git LFS repositories)

Dependencies are automatically installed when run with sudo privileges.

## License

This project is open source and available under the MIT License.