// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

contract DisasterRegistry is 
    Initializable, 
    AccessControlUpgradeable, 
    PausableUpgradeable 
{
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant DATA_PROVIDER_ROLE = keccak256("DATA_PROVIDER_ROLE");
    
    enum DisasterStatus { ACTIVE, RESOLVED, ARCHIVED }
    
    struct Disaster {
        string id;
        string name;
        string description;
        string location;
        uint256 startDate;
        uint256 endDate;
        string imageUrl;
        string externalSource;
        DisasterStatus status;
        uint256 createdAt;
        uint256 updatedAt;
        address createdBy;
    }
    
    // State variables
    mapping(string => Disaster) public disasters;
    mapping(string => bool) public disasterExists;
    string[] public disasterIds;
    mapping(address => string[]) public disastersByProvider;
    
    // Events
    event DisasterRegistered(
        string indexed disasterId,
        string name,
        string location,
        address indexed provider,
        uint256 timestamp
    );
    
    event DisasterUpdated(
        string indexed disasterId,
        DisasterStatus status,
        uint256 timestamp
    );
    
    event DisasterStatusChanged(
        string indexed disasterId,
        DisasterStatus oldStatus,
        DisasterStatus newStatus,
        uint256 timestamp
    );
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    function initialize() public initializer {
        __AccessControl_init();
        __Pausable_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(DATA_PROVIDER_ROLE, msg.sender);
    }
    
    modifier disasterNotExists(string memory disasterId) {
        require(!disasterExists[disasterId], "Disaster already exists");
        _;
    }
    
    modifier disasterExistsModifier(string memory disasterId) {
        require(disasterExists[disasterId], "Disaster does not exist");
        _;
    }
    
    /**
     * @notice Registers a new disaster
     * @param disasterId Unique disaster ID
     * @param name Disaster name
     * @param description Disaster description
     * @param location Location
     * @param startDate Start date
     * @param endDate End date (0 if ongoing)
     * @param imageUrl Image URL
     * @param externalSource Data source
     */
    function registerDisaster(
        string memory disasterId,
        string memory name,
        string memory description,
        string memory location,
        uint256 startDate,
        uint256 endDate,
        string memory imageUrl,
        string memory externalSource
    ) 
        external 
        onlyRole(DATA_PROVIDER_ROLE) 
        disasterNotExists(disasterId) 
        whenNotPaused 
    {
        require(bytes(disasterId).length > 0, "Disaster ID required");
        require(bytes(name).length > 0, "Disaster name required");
        require(bytes(location).length > 0, "Location required");
        require(startDate <= block.timestamp, "Start date cannot be in the future");
        
        disasters[disasterId] = Disaster({
            id: disasterId,
            name: name,
            description: description,
            location: location,
            startDate: startDate,
            endDate: endDate,
            imageUrl: imageUrl,
            externalSource: externalSource,
            status: DisasterStatus.ACTIVE,
            createdAt: block.timestamp,
            updatedAt: block.timestamp,
            createdBy: msg.sender
        });
        
        disasterExists[disasterId] = true;
        disasterIds.push(disasterId);
        disastersByProvider[msg.sender].push(disasterId);
        
        emit DisasterRegistered(disasterId, name, location, msg.sender, block.timestamp);
    }
    
    /**
     * @notice Updates disaster status
     * @param disasterId Disaster ID
     * @param newStatus New status
     */
    function updateDisasterStatus(string memory disasterId, DisasterStatus newStatus) 
        external 
        onlyRole(DATA_PROVIDER_ROLE) 
        disasterExistsModifier(disasterId) 
        whenNotPaused 
    {
        DisasterStatus oldStatus = disasters[disasterId].status;
        require(oldStatus != newStatus, "Status is already set to this value");
        
        disasters[disasterId].status = newStatus;
        disasters[disasterId].updatedAt = block.timestamp;
        
        // Set end date when the disaster is resolved
        if (newStatus == DisasterStatus.RESOLVED && disasters[disasterId].endDate == 0) {
            disasters[disasterId].endDate = block.timestamp;
        }
        
        emit DisasterStatusChanged(disasterId, oldStatus, newStatus, block.timestamp);
        emit DisasterUpdated(disasterId, newStatus, block.timestamp);
    }
    
    /**
     * @notice Updates disaster information
     * @param disasterId Disaster ID
     * @param description New description
     * @param imageUrl New image URL
     */
    function updateDisasterInfo(
        string memory disasterId,
        string memory description,
        string memory imageUrl
    ) 
        external 
        onlyRole(DATA_PROVIDER_ROLE) 
        disasterExistsModifier(disasterId) 
        whenNotPaused 
    {
        disasters[disasterId].description = description;
        disasters[disasterId].imageUrl = imageUrl;
        disasters[disasterId].updatedAt = block.timestamp;
        
        emit DisasterUpdated(disasterId, disasters[disasterId].status, block.timestamp);
    }
    
    /**
     * @notice Gets disaster information
     * @param disasterId Disaster ID
     */
    function getDisaster(string memory disasterId) 
        external 
        view 
        disasterExistsModifier(disasterId) 
        returns (Disaster memory) 
    {
        return disasters[disasterId];
    }
    
    /**
     * @notice Gets active disasters
     */
    function getActiveDisasters() external view returns (string[] memory) {
        uint256 activeCount = 0;
        
        // Calculate active disaster count
        for (uint256 i = 0; i < disasterIds.length; i++) {
            if (disasters[disasterIds[i]].status == DisasterStatus.ACTIVE) {
                activeCount++;
            }
        }
        
        // Create active disaster array
        string[] memory activeDisasters = new string[](activeCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < disasterIds.length; i++) {
            if (disasters[disasterIds[i]].status == DisasterStatus.ACTIVE) {
                activeDisasters[index] = disasterIds[i];
                index++;
            }
        }
        
        return activeDisasters;
    }
    
    /**
     * @notice Gets total disaster count
     */
    function getTotalDisasterCount() external view returns (uint256) {
        return disasterIds.length;
    }
    
    /**
     * @notice Gets disasters by provider
     */
    function getDisastersByProvider(address provider) 
        external 
        view 
        returns (string[] memory) 
    {
        return disastersByProvider[provider];
    }
    
    // Emergency functions
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
}
