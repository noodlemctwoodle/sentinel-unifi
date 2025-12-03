# Sentinel UniFi Integration - Documentation

This directory contains all documentation for the Sentinel UniFi integration project.

## Documentation Structure

### Getting Started

- **[../README.md](../README.md)** - Main testing guide and quick start

### Component Documentation

#### Data Collection

- **[Collector/README.md](Collector/README.md)** - Linux collector installation, configuration, and troubleshooting
- **[Collector/API-TESTING.md](Collector/API-TESTING.md)** - API connectivity testing and validation

#### Azure Infrastructure

- **[DCR/README.md](DCR/README.md)** - Data Collection Rules deployment and configuration
- **[DCR/TRANSFORMATIONS.md](DCR/TRANSFORMATIONS.md)** - Detailed KQL transformations for 16 data types (Events documented separately)
- **[DCR/EVENTS-PARSING.md](DCR/EVENTS-PARSING.md)** - Intelligent event parsing and categorization

## Quick Navigation

### For Testers

1. Start with the [main testing guide](../README.md)
2. **Optional:** Test API connectivity first with [Collector/API-TESTING.md](Collector/API-TESTING.md)
3. Follow the deployment steps in [DCR/README.md](DCR/README.md)
4. Install the collector using [Collector/README.md](Collector/README.md)
5. Verify data flow and run test scenarios

### For Security Analysts

- **Event Intelligence**: [DCR/EVENTS-PARSING.md](DCR/EVENTS-PARSING.md)
- **Sample KQL Queries**: See the Events Parsing guide for security-focused queries

### For Developers

- **Transformation Logic**: [DCR/TRANSFORMATIONS.md](DCR/TRANSFORMATIONS.md)
- **Collector Scripts**: Located in `../Collector/` directory
- **ARM Templates**: Located in `../DCR/` directory

## Documentation Updates

When updating documentation:

- Keep the main README focused on testing and quick start
- Add technical details to component-specific READMEs
- Update this index when adding new documentation files

**Current Version:** 2.1.0
**Last Updated:** December 2025
