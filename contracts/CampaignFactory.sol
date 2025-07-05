// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./Campaign.sol";

contract CampaignFactory is 
    Initializable, 
    AccessControlUpgradeable, 
    PausableUpgradeable 
{
    using Clones for address;
    
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant ORGANIZER_ROLE = keccak256("ORGANIZER_ROLE");
    
    address public campaignImplementation;
    address public userContract;
    address public disasterRegistry;
    
    struct CampaignInfo {
        address campaignAddress;
        string disasterId;
        address organizer;
        string name;
        uint256 startDate;
        uint256 endDate;
        uint256 createdAt;
        bool isActive;
    }
    
    // State variables
    mapping(uint256 => CampaignInfo) public campaigns;
    mapping(string => uint256[]) public campaignsByDisaster;
    mapping(address => uint256[]) public campaignsByOrganizer;
    uint256 public nextCampaignId;
    uint256[] public allCampaignIds;
    
    // Events
    event CampaignCreated(
        uint256 indexed campaignId,
        address indexed campaignAddress,
        string indexed disasterId,
        address organizer,
        string name,
        uint256 timestamp
    );
    
    event CampaignDeactivated(
        uint256 indexed campaignId,
        address indexed campaignAddress,
        uint256 timestamp
    );
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    function initialize(
        address _campaignImplementation,
        address _userContract,
        address _disasterRegistry
    ) public initializer {
        __AccessControl_init();
        __Pausable_init();
        
        require(_campaignImplementation != address(0), "Invalid campaign implementation");
        require(_userContract != address(0), "Invalid user contract");
        require(_disasterRegistry != address(0), "Invalid disaster registry");
        
        campaignImplementation = _campaignImplementation;
        userContract = _userContract;
        disasterRegistry = _disasterRegistry;
        nextCampaignId = 1;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }
    
    /**
     * @notice Creates a new campaign
     * @param disasterId Disaster ID
     * @param name Campaign name
     * @param description Campaign description
     * @param startDate Start date
     * @param endDate End date
     * @param supportItems Array of support items/services
     * @param imageUrl Campaign image URL
     */
    function createCampaign(
        string memory disasterId,
        string memory name,
        string memory description,
        uint256 startDate,
        uint256 endDate,
        string[] memory supportItems,
        string memory imageUrl
    ) 
        external 
        onlyRole(ORGANIZER_ROLE) 
        whenNotPaused 
        returns (uint256 campaignId, address campaignAddress) 
    {
        require(bytes(disasterId).length > 0, "Disaster ID required");
        require(bytes(name).length > 0, "Campaign name required");
        require(startDate >= block.timestamp, "Start date must be in the future");
        require(endDate > startDate, "End date must be after start date");
        require(supportItems.length > 0, "At least one support item required");
        
        // Check if the disaster exists
        require(
            IDisasterRegistry(disasterRegistry).disasterExists(disasterId), 
            "Disaster does not exist"
        );
        
        campaignId = nextCampaignId++;
        
        // Clone pattern to create new campaign (gas saving)
        campaignAddress = campaignImplementation.clone();
        
        // Initialize campaign
        Campaign(campaignAddress).initialize(
            campaignId,
            disasterId,
            msg.sender,
            name,
            description,
            startDate,
            endDate,
            supportItems,
            imageUrl,
            userContract
        );
        
        // Store campaign information
        campaigns[campaignId] = CampaignInfo({
            campaignAddress: campaignAddress,
            disasterId: disasterId,
            organizer: msg.sender,
            name: name,
            startDate: startDate,
            endDate: endDate,
            createdAt: block.timestamp,
            isActive: true
        });
        
        // Update arrays for indexing
        campaignsByDisaster[disasterId].push(campaignId);
        campaignsByOrganizer[msg.sender].push(campaignId);
        allCampaignIds.push(campaignId);
        
        emit CampaignCreated(
            campaignId,
            campaignAddress,
            disasterId,
            msg.sender,
            name,
            block.timestamp
        );
    }
    
    /**
     * @notice Deactivate a campaign
     * @param campaignId Campaign ID
     */
    function deactivateCampaign(uint256 campaignId) 
        external 
        onlyRole(ADMIN_ROLE) 
        whenNotPaused 
    {
        require(campaigns[campaignId].campaignAddress != address(0), "Campaign does not exist");
        require(campaigns[campaignId].isActive, "Campaign already deactivated");
        
        campaigns[campaignId].isActive = false;
        
        // Pause the campaign contract
        Campaign(campaigns[campaignId].campaignAddress).emergencyPause();
        
        emit CampaignDeactivated(
            campaignId,
            campaigns[campaignId].campaignAddress,
            block.timestamp
        );
    }
    
    /**
     * @notice Get active campaigns for a specific disaster
     * @param disasterId Disaster ID
     */
    function getActiveCampaignsByDisaster(string memory disasterId) 
        external 
        view 
        returns (uint256[] memory) 
    {
        uint256[] memory disasterCampaigns = campaignsByDisaster[disasterId];
        uint256 activeCount = 0;
        
        // Calculate active campaign count
        for (uint256 i = 0; i < disasterCampaigns.length; i++) {
            if (campaigns[disasterCampaigns[i]].isActive && 
                block.timestamp <= campaigns[disasterCampaigns[i]].endDate) {
                activeCount++;
            }
        }
        
        // Create active campaign array
        uint256[] memory activeCampaigns = new uint256[](activeCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < disasterCampaigns.length; i++) {
            if (campaigns[disasterCampaigns[i]].isActive && 
                block.timestamp <= campaigns[disasterCampaigns[i]].endDate) {
                activeCampaigns[index] = disasterCampaigns[i];
                index++;
            }
        }
        
        return activeCampaigns;
    }
    
    /**
     * @notice Get campaign information
     */
    function getCampaignInfo(uint256 campaignId) 
        external 
        view 
        returns (CampaignInfo memory) 
    {
        require(campaigns[campaignId].campaignAddress != address(0), "Campaign does not exist");
        return campaigns[campaignId];
    }
    
    /**
     * @notice Get campaigns by organizer
     */
    function getCampaignsByOrganizer(address organizer) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return campaignsByOrganizer[organizer];
    }
    
    /**
     * @notice Get total campaign count
     */
    function getTotalCampaignCount() external view returns (uint256) {
        return allCampaignIds.length;
    }
    
    // Emergency functions
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
    
    function updateCampaignImplementation(address _newImplementation) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(_newImplementation != address(0), "Invalid implementation address");
        campaignImplementation = _newImplementation;
    }
}

// Interface for DisasterRegistry
interface IDisasterRegistry {
    function disasterExists(string memory disasterId) external view returns (bool);
}
