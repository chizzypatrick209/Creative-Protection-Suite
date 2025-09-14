# Content Protection Platform Smart Contract

## Overview

The Content Protection Platform is a comprehensive smart contract built on the Stacks blockchain that enables creators to register, protect, and monetize their digital content through a decentralized licensing system. The platform provides robust content management, licensing mechanisms, royalty distribution, and dispute resolution capabilities.

## Features

### Core Functionality
- **Content Registration**: Creators can register digital content with metadata, pricing, and royalty settings
- **Multi-tier Licensing**: Support for commercial, personal, and educational license types with dynamic pricing
- **Automated Royalty Distribution**: Built-in royalty splits and platform fee management
- **User Profile Management**: Comprehensive user profiles with verification system
- **Dispute Resolution**: Formal dispute filing and resolution system with moderated oversight

### Key Capabilities
- Flexible license duration management
- Real-time license validation
- Revenue tracking and analytics
- Moderated content disputes
- Multi-recipient royalty splits
- Platform fee configuration

## Contract Architecture

### Data Structures

#### Content Registry
- Stores content metadata, pricing, and statistics
- Tracks creator information and revenue
- Manages content activation status

#### License Management
- Records all license purchases and terms
- Tracks license validity and expiration
- Maps user-content relationships for efficient lookup

#### User Profiles
- Maintains user information and verification status
- Tracks content creation and earnings
- Includes reputation scoring system

#### Dispute System
- Formal complaint filing mechanism
- Multi-stage resolution process
- Moderated oversight capabilities

## Usage Guide

### For Content Creators

#### Register Content
```clarity
(register-content 
  "Content Title" 
  "Content description" 
  "content-hash-sha256" 
  1000000 ;; Price in microSTX
  500)    ;; 5% royalty
```

#### Update Content Settings
```clarity
;; Update pricing
(update-license-price content-id 2000000)

;; Toggle content availability
(update-content-status content-id true)
```

#### Add Royalty Recipients
```clarity
(add-royalty-split content-id recipient-principal 1000) ;; 10%
```

### For Content Consumers

#### Purchase License
```clarity
(purchase-license 
  content-id 
  "commercial" 
  52560) ;; Duration in blocks (~1 year)
```

#### Check License Status
```clarity
(is-content-licensed-by-user content-id user-principal)
```

### For Platform Administration

#### Add Moderators
```clarity
(add-moderator moderator-principal)
```

#### Update Platform Settings
```clarity
(update-platform-fee 300) ;; 3% platform fee
```

## License Types and Pricing

### License Tiers
- **Personal**: Base price (1x multiplier)
- **Educational**: Discounted rate (0.5x multiplier)
- **Commercial**: Premium rate (2x multiplier)

### Duration Limits
- **Minimum**: 1 day (86,400 blocks)
- **Maximum**: 1 year (52,560 blocks)
- Configurable by contract owner

## Fee Structure

### Platform Fees
- Default: 2.5% of all license purchases
- Configurable by contract owner (maximum 10%)
- Automatically deducted during license purchases

### Royalty Distribution
- Creators set royalty percentage (0-100%)
- Support for multiple royalty recipients
- Automatic distribution on license purchases

## Security Features

### Access Control
- Owner-only administrative functions
- Creator-only content management
- Moderator-based dispute resolution

### Validation
- Comprehensive input validation
- Principal address verification
- License type and duration validation

### Error Handling
- Detailed error codes for all failure scenarios
- Graceful handling of edge cases
- Clear error messaging

## Error Codes

| Code | Description |
|------|-------------|
| 100  | Owner only operation |
| 101  | Resource not found |
| 102  | Unauthorized access |
| 103  | Resource already exists |
| 104  | Invalid amount |
| 105  | Insufficient balance |
| 106  | Invalid license type |
| 107  | Content not active |
| 108  | License expired |
| 109  | Invalid dispute status |
| 110  | Invalid percentage |
| 111  | Invalid duration |
| 112  | Transfer failed |
| 113  | Invalid input |

## Read-Only Functions

### Content Information
- `get-content-info`: Retrieve content metadata
- `get-license-info`: Get license details
- `calculate-license-fee`: Calculate pricing for license types

### User Management
- `get-user-profile`: Retrieve user profile information
- `is-content-licensed-by-user`: Check user license status

### Platform Settings
- `get-platform-fee-percentage`: Current platform fee rate
- `get-contract-owner`: Contract owner address

## Deployment Requirements

### Prerequisites
- Stacks blockchain access
- STX tokens for transaction fees
- Clarity smart contract deployment capabilities

### Configuration
1. Deploy contract to Stacks blockchain
2. Set initial platform fee percentage
3. Configure license duration limits
4. Add initial moderators if required

## Best Practices

### For Creators
- Use descriptive titles and comprehensive descriptions
- Set competitive but fair pricing
- Regularly monitor license activity
- Respond promptly to disputes

### For Consumers
- Verify content authenticity before licensing
- Choose appropriate license type for use case
- Respect license terms and duration
- Report copyright violations through dispute system

### For Administrators
- Regular monitoring of dispute queue
- Fair and transparent dispute resolution
- Appropriate platform fee management
- Active moderation of content quality

## Technical Considerations

### Block Height Usage
- All timestamps use Stacks block height
- License durations measured in blocks
- Approximately 144 blocks per day

### Gas Optimization
- Efficient lookup mechanisms
- Minimal storage operations
- Optimized validation functions

### Scalability
- Map-based data structures for efficient access
- Indexed user-content relationships
- Modular function architecture