# EmuBot - EverQuest Bot Management System

A comprehensive bot management and inventory system for EverQuest, built for MacroQuest environments. EmuBot provides advanced inventory tracking, item scanning, upgrade analysis, and group management capabilities for your bot characters.

## Features

### 📦 **Bot Inventory Management**
- **Real-time Inventory Tracking**: Automatically captures and caches bot inventory data in SQLite database
- **Visual Item Browser**: Browse equipped items and inventory with detailed stats (AC, HP, Mana, etc.)
- **Smart Refresh**: Detects inventory changes and auto-scans items with missing or outdated stats
- **Bulk Operations**: Scan all bots at once with configurable camping behavior

### 🔍 **Item Scanning & Analysis**
- **Automated Item Stats**: Uses `^itemstats` to gather comprehensive item data
- **Mismatch Detection**: Automatically identifies items needing stat updates after inventory refresh
- **Queue Management**: Efficiently processes item scanning with visual progress tracking
- **Database Persistence**: All item stats cached locally for instant access

### ⚡ **Upgrade System**
- **Cursor Item Analysis**: Analyze items on your cursor for potential bot upgrades
- **Class Compatibility**: Automatically filters upgrade candidates by class restrictions
- **Comparison View**: Side-by-side stat comparison (AC/HP/Mana) between current and upgrade items
- **One-Click Swapping**: Direct item transfer to bots via `^ig` commands
- **Multiple Detection Methods**: 
  - Local scanning using cached inventory data
  - Network polling via `^iu` bot responses

### 👥 **Bot Group Management**
- **Custom Groups**: Create and manage groups of bots for coordinated operations
- **Quick Actions**: One-click spawn and invite entire groups
- **Persistent Storage**: Group configurations saved to database
- **Visual Management**: Drag-and-drop interface for adding/removing bots from groups

### 🎛️ **Advanced Controls**
- **No Camp Mode**: Toggle to disable automatic camping during scan operations
- **Export Functionality**: Export bot data to JSON/CSV for external analysis
- **Multi-Tab Interface**: Organized UI with separate tabs for different functions
- **Real-Time Status**: Live bot spawn status and inventory counts

## Installation

1. Place the EmuBot folder in your MacroQuest `lua` directory
2. Load the script in-game: `/lua run EmuBot`
3. The system will automatically create the SQLite database on first run

## Usage

### Basic Workflow
1. **Capture Bots**: Click "Refresh Bot List" to discover available bots
2. **Scan Inventory**: Use "Scan All Bots" to populate the database with current inventory
3. **Analyze Upgrades**: Put potential upgrade items on cursor and use the Upgrades tab
4. **Manage Groups**: Create bot groups for easy spawning and management

### Key Commands
- **Bot Creation**: `^botcreate <name> <class> <race> <gender>`
- **Item Stats**: `^itemstats` (automatically used by scanning system)
- **Item Give**: `^ig byname <botname>` (used by upgrade system)
- **Inventory Update**: `^iu` (triggers bot inventory responses)

## Technical Details

### Database Schema
- **bots**: Bot metadata (name, class, level)
- **bot_inventory**: Item data with comprehensive stats
- **bot_groups**: Custom group definitions
- **bot_group_members**: Group membership relationships

### Architecture
- **Modular Design**: Separate modules for inventory, upgrades, groups, and management
- **Event-Driven**: Uses MacroQuest event system for bot communication
- **Async Operations**: Non-blocking UI with background task processing
- **ImGui Interface**: Modern, responsive user interface

### Performance
- **SQLite Caching**: Fast local data access with persistent storage
- **Efficient Scanning**: Smart queue management prevents bot overload
- **Minimal Network Traffic**: Cached results reduce repetitive bot commands

## Configuration

### Settings Tab Options
- **No Camp Toggle**: Disable automatic camping during scan operations
- **Auto-refresh**: Automatically detect and scan inventory changes
- **Export Options**: Configure data export formats and destinations

### Bot Groups
- Create named groups for different purposes (raid teams, farming groups, etc.)
- Quick spawn/invite for entire groups
- Persistent group configurations

## Requirements

- **MacroQuest**: Compatible with modern MQ installations
- **EverQuest Server**: Designed for servers supporting bot commands (`^botcreate`, `^itemstats`, etc.)
- **Lua Environment**: Requires MQ Lua plugin with ImGui support
- **Database**: Uses SQLite (no external database required)

## Contributing

This project welcomes contributions! Areas for enhancement:
- Additional item stat categories
- Advanced filtering and search capabilities
- Integration with other MQ plugins
- Performance optimizations
- UI/UX improvements

## License

This project is provided as-is for the EverQuest community. Please respect server rules and terms of service when using automation tools.

---

**Note**: This tool is designed for educational and convenience purposes. Always follow your server's rules regarding automation and bot usage.