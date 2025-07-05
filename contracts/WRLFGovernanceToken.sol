// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

contract WRLFGovernanceToken is 
    Initializable,
    ERC20Upgradeable,
    ERC20VotesUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");
    
    address public treasuryContract;
    uint256 public totalMintedFromDonations;
    
    mapping(address => uint256) public mintedFromDonations;
    mapping(uint256 => uint256) public donationToTokenMapping; // donationId => amount minted
    
    // Events
    event TokensMintedFromDonation(
        address indexed recipient,
        uint256 indexed donationId,
        uint256 amount,
        uint256 timestamp
    );
    
    event TreasuryContractUpdated(
        address indexed oldTreasury,
        address indexed newTreasury,
        uint256 timestamp
    );
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    function initialize(address _treasuryContract) public initializer {
        __ERC20_init("Wrld Relief Foundation Token", "WRLF");
        __ERC20Permit_init("Wrld Relief Foundation Token");
        __ERC20Votes_init();
        __AccessControl_init();
        __Pausable_init();
        
        require(_treasuryContract != address(0), "Invalid treasury contract");
        treasuryContract = _treasuryContract;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(TREASURY_ROLE, _treasuryContract);
    }
    
    /**
     * @notice Mints tokens in response to a donation
     * @param recipient The recipient of the tokens
     * @param donationId The donation ID (for tracking)
     * @param amount The amount of tokens to mint (equal to the Treasury deposit amount)
     */
    function mintFromDonation(
        address recipient,
        uint256 donationId,
        uint256 amount
    ) 
        external 
        onlyRole(MINTER_ROLE) 
        whenNotPaused 
    {
        require(recipient != address(0), "Invalid recipient address");
        require(amount > 0, "Amount must be greater than 0");
        require(donationToTokenMapping[donationId] == 0, "Tokens already minted for this donation");
        
        // Mint tokens
        _mint(recipient, amount);
        
        // Update records
        mintedFromDonations[recipient] += amount;
        totalMintedFromDonations += amount;
        donationToTokenMapping[donationId] = amount;
        
        emit TokensMintedFromDonation(recipient, donationId, amount, block.timestamp);
    }
    
    /**
     * @notice Mints governance tokens from the Treasury
     * @param recipient The recipient of the tokens
     * @param amount The amount of tokens to mint
     */
    function mintForGovernance(address recipient, uint256 amount) 
        external 
        onlyRole(TREASURY_ROLE) 
        whenNotPaused 
    {
        require(recipient != address(0), "Invalid recipient address");
        require(amount > 0, "Amount must be greater than 0");
        
        _mint(recipient, amount);
    }
    
    /**
     * @notice Updates the Treasury contract address
     * @param newTreasury The new Treasury contract address
     */
    function updateTreasuryContract(address newTreasury) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(newTreasury != address(0), "Invalid treasury address");
        require(newTreasury != treasuryContract, "Same treasury address");
        
        address oldTreasury = treasuryContract;
        
        // Revoke previous Treasury role
        _revokeRole(TREASURY_ROLE, oldTreasury);
        
        // Grant new Treasury role
        _grantRole(TREASURY_ROLE, newTreasury);
        
        treasuryContract = newTreasury;
        
        emit TreasuryContractUpdated(oldTreasury, newTreasury, block.timestamp);
    }
    
    /**
     * @notice Retrieves the amount of tokens minted for a specific donor
     */
    function getDonationTokens(address user) external view returns (uint256) {
        return mintedFromDonations[user];
    }
    
    /**
     * @notice Retrieves the amount of tokens minted for a specific donation
     */
    function getTokensByDonation(uint256 donationId) external view returns (uint256) {
        return donationToTokenMapping[donationId];
    }
    
    /**
     * @notice Retrieves the total amount of tokens minted from donations
     */
    function getTotalDonationTokens() external view returns (uint256) {
        return totalMintedFromDonations;
    }
    
    /**
     * @notice Burns tokens
     * @param amount The amount of tokens to burn
     */
    function burn(uint256 amount) external whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        _burn(msg.sender, amount);
    }
    
    /**
     * @notice Burns tokens from another user (only admins)
     * @param account The account to burn tokens from
     * @param amount The amount of tokens to burn
     */
    function burnFrom(address account, uint256 amount) 
        external 
        onlyRole(ADMIN_ROLE) 
        whenNotPaused 
    {
        require(account != address(0), "Invalid account address");
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(account) >= amount, "Insufficient balance");
        
        _burn(account, amount);
    }
    
    // Emergency functions
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
    
    // Required overrides
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20Upgradeable) whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }
    
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20Upgradeable, ERC20VotesUpgradeable) {
        super._afterTokenTransfer(from, to, amount);
    }
    
    function _mint(address to, uint256 amount)
        internal
        virtual
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._mint(to, amount);
    }
    
    function _burn(address account, uint256 amount)
        internal
        virtual
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._burn(account, amount);
    }
}
